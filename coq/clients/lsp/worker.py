from asyncio import as_completed
from typing import AsyncIterator, Iterator, Sequence

from std2.aitertools import anext
from std2.itertools import chunk

from ...lsp.requests.completion import request
from ...lsp.types import LSPcomp
from ...shared.fuzzy import quick_ratio
from ...shared.parse import is_word, lower
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context
from ..cache.worker import CacheWorker


class Worker(BaseWorker[BaseClient, None], CacheWorker):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        self._local_cache = False
        CacheWorker.__init__(self, supervisor=supervisor)
        BaseWorker.__init__(self, supervisor=supervisor, options=options, misc=misc)

    async def work(self, context: Context) -> AsyncIterator[Sequence[Completion]]:
        w_before, sw_before = lower(context.words_before), lower(context.syms_before)
        self._local_cache, cached, set_cache = self._use_cache(context)

        async def cached_items() -> LSPcomp:
            items = await cached
            return LSPcomp(local_cache=False, items=items)

        async def stream() -> AsyncIterator[LSPcomp]:
            stream = request(
                self._supervisor.nvim,
                short_name=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                context=context,
            )
            for fut in as_completed(
                (
                    cached_items(),
                    anext(stream, LSPcomp(local_cache=False, items=iter(()))),
                )
            ):
                yield await fut

            async for lc in stream:
                yield lc

        async for lsp_comps in stream():
            for chunked in chunk(
                lsp_comps.items, n=self._supervisor.options.max_results
            ):

                def cont() -> Iterator[Completion]:
                    for c in chunked:
                        cword = (
                            w_before
                            if is_word(
                                c.sort_by[:1],
                                unifying_chars=self._supervisor.options.unifying_chars,
                            )
                            else sw_before
                        )
                        go = (
                            quick_ratio(
                                cword,
                                lower(c.sort_by),
                                look_ahead=self._supervisor.options.look_ahead,
                            )
                            >= self._supervisor.options.fuzzy_cutoff
                        )
                        if go:
                            yield c

                yield tuple(cont())

                if lsp_comps.local_cache and chunked:
                    await set_cache(chunked)
                    yield ()

