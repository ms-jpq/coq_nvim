from asyncio import as_completed, gather
from enum import Enum, auto
from itertools import chain
from typing import AsyncIterator, Iterator, MutableSequence, Optional, Tuple

from std2 import anext
from std2.aitertools import to_async
from std2.asyncio import pure
from std2.itertools import chunk

from ...lsp.requests.completion import comp_lsp
from ...lsp.types import LSPcomp
from ...shared.context import cword_before
from ...shared.fuzzy import multi_set_ratio
from ...shared.parse import lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.sql import BIGGEST_INT
from ...shared.types import Completion, Context, SnippetEdit
from ..cache.worker import CacheWorker, sanitize_cached


class _Src(Enum):
    from_db = auto()
    from_stored = auto()
    from_query = auto()


class Worker(BaseWorker[BaseClient, None], CacheWorker):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._local_cached: MutableSequence[Iterator[Completion]] = []
        CacheWorker.__init__(self, supervisor=supervisor)
        BaseWorker.__init__(self, supervisor=supervisor, options=options, misc=misc)

    def _request(self, context: Context) -> AsyncIterator[LSPcomp]:
        return comp_lsp(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            weight_adjust=self._options.weight_adjust,
            context=context,
        )

    async def work(self, context: Context) -> AsyncIterator[Optional[Completion]]:
        limit = BIGGEST_INT if context.manual else self._supervisor.options.max_results

        use_cache, cached, set_cache = self._use_cache(context)
        if not use_cache:
            self._local_cached.clear()

        async def cached_iters() -> Tuple[_Src, LSPcomp]:
            items = map(sanitize_cached, chain(*self._local_cached))
            self._local_cached.clear()
            return _Src.from_stored, LSPcomp(local_cache=True, items=items)

        async def cached_db_items() -> Tuple[_Src, LSPcomp]:
            items = await cached
            return _Src.from_db, LSPcomp(local_cache=False, items=items)

        async def stream() -> AsyncIterator[Tuple[_Src, LSPcomp]]:
            do_ask = context.manual or not use_cache
            stream = self._request(context) if do_ask else to_async(())

            for fut in as_completed(
                (
                    cached_iters(),
                    cached_db_items(),
                    gather(
                        pure(_Src.from_query),
                        anext(stream, LSPcomp(local_cache=False, items=iter(()))),
                    ),
                )
            ):
                yield await fut

            async for lc in stream:
                yield _Src.from_query, lc

        seen = 0
        async for src, lsp_comps in stream():
            if lsp_comps.local_cache:
                self._local_cached.append(lsp_comps.items)

            for chunked in chunk(
                lsp_comps.items, n=self._supervisor.options.max_results
            ):
                if seen <= limit:
                    if src is _Src.from_db:
                        for comp in chunked:
                            yield comp
                            seen += 1
                    else:
                        for comp in chunked:
                            cword = cword_before(
                                self._supervisor.options.unifying_chars,
                                lower=True,
                                context=context,
                                sort_by=comp.sort_by,
                            )
                            if len(
                                comp.sort_by
                            ) + self._supervisor.options.look_ahead >= len(cword):
                                ratio = multi_set_ratio(
                                    cword,
                                    lower(comp.sort_by),
                                    look_ahead=self._supervisor.options.look_ahead,
                                )
                                if ratio >= self._supervisor.options.fuzzy_cutoff and (
                                    isinstance(comp.primary_edit, SnippetEdit)
                                    or not cword.startswith(comp.primary_edit.new_text)
                                ):
                                    yield comp
                                    seen += 1

                if lsp_comps.local_cache and chunked:
                    await set_cache(chunked)
                    yield None
