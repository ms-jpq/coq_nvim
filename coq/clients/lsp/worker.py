from asyncio import sleep
from enum import Enum, auto
from typing import AbstractSet, AsyncIterator, Iterator, MutableMapping, Optional, Tuple

from std2.aitertools import merge
from std2.itertools import chunk

from ...lsp.requests.completion import comp_lsp
from ...lsp.types import LSPcomp
from ...shared.fuzzy import multi_set_ratio
from ...shared.parse import lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient, MatchOptions
from ...shared.sql import BIGGEST_INT
from ...shared.trans import cword_before
from ...shared.types import Completion, Context, Edit, SnippetEdit
from ..cache.worker import CacheWorker, sanitize_cached

_CHUNK_SIZE = 9


class _Src(Enum):
    from_db = auto()
    from_stored = auto()
    from_query = auto()


def _use_comp(match: MatchOptions, context: Context, sort_by: str, edit: Edit) -> bool:
    cword = cword_before(
        match.unifying_chars,
        lower=True,
        context=context,
        sort_by=sort_by,
    )
    if len(sort_by) + match.look_ahead >= len(cword):
        ratio = multi_set_ratio(
            cword,
            lower(sort_by),
            look_ahead=match.look_ahead,
        )
        use = ratio >= match.fuzzy_cutoff and (
            isinstance(edit, SnippetEdit) or not cword.startswith(edit.new_text)
        )
        return use
    else:
        return False


def _fast_comp(
    look_ahead: int,
    lower_word: str,
    lower_word_prefix: str,
    sort_by: str,
) -> bool:
    if not lower_word_prefix:
        return True
    else:
        lo = lower(sort_by)
        return lo[:look_ahead] == lower_word_prefix and not lower_word.startswith(lo)


class Worker(BaseWorker[BaseClient, None]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        self._cache = CacheWorker(supervisor)
        self._local_cached: MutableMapping[
            Optional[str], Tuple[Iterator[Completion], int]
        ] = {}

    def _request(
        self, context: Context, cached_clients: AbstractSet[str]
    ) -> AsyncIterator[LSPcomp]:
        return comp_lsp(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            weight_adjust=self._options.weight_adjust,
            context=context,
            clients=set() if context.manual else cached_clients,
        )

    async def work(self, context: Context) -> AsyncIterator[Optional[Completion]]:
        limit = BIGGEST_INT if context.manual else self._supervisor.match.max_results
        chunk_size = self._supervisor.match.max_results // 2 + 1
        fast_limit = self._supervisor.match.max_results * 3
        lower_word_prefix = context.l_words_before[: self._supervisor.match.look_ahead]

        use_cache, cached_clients, cached, set_cache = self._cache._use(context)
        if not use_cache:
            self._local_cached.clear()

        async def cached_db_items() -> AsyncIterator[Tuple[_Src, LSPcomp]]:
            items, length = await cached
            yield _Src.from_db, LSPcomp(
                client=None, local_cache=False, items=items, length=length
            )

        async def cached_iters() -> AsyncIterator[Tuple[_Src, LSPcomp]]:
            acc = {**self._local_cached}
            self._local_cached.clear()

            for client, (cached_items, length) in acc.items():
                items = (sanitize_cached(item, sort_by=None) for item in cached_items)
                yield _Src.from_stored, LSPcomp(
                    client=client, local_cache=True, items=items, length=length
                )

        async def lsp_items() -> AsyncIterator[Tuple[_Src, LSPcomp]]:
            if context.manual or not use_cache:
                async for lsp_comps in self._request(
                    context, cached_clients=cached_clients
                ):
                    yield _Src.from_query, lsp_comps

        stream = merge(cached_db_items(), cached_iters(), lsp_items())
        seen = 0
        async for src, lsp_comps in stream:
            if lsp_comps.local_cache:
                if lsp_comps.length:
                    self._local_cached[lsp_comps.client] = (
                        lsp_comps.items,
                        lsp_comps.length,
                    )

            n = chunk_size if seen < limit else _CHUNK_SIZE
            for chunked in chunk(lsp_comps.items, n=n):
                if seen < limit:
                    if src is _Src.from_db:
                        for comp in chunked:
                            if seen < limit:
                                seen += 1
                                yield comp
                    else:
                        fast_search = lsp_comps.length > fast_limit
                        for comp in chunked:
                            if seen < limit:
                                if (
                                    _fast_comp(
                                        self._supervisor.match.look_ahead,
                                        lower_word=context.l_words_before,
                                        lower_word_prefix=lower_word_prefix,
                                        sort_by=comp.sort_by,
                                    )
                                    if fast_search
                                    else _use_comp(
                                        self._supervisor.match,
                                        context=context,
                                        sort_by=comp.sort_by,
                                        edit=comp.primary_edit,
                                    )
                                ):
                                    seen += 1
                                    yield comp
                else:
                    await sleep(1 / 1000)

                if lsp_comps.local_cache and chunked:
                    await set_cache(lsp_comps.client, chunked)
                    yield None
