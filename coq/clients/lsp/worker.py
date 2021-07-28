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
        CacheWorker.__init__(self, supervisor=supervisor)
        BaseWorker.__init__(self, supervisor=supervisor, options=options, misc=misc)

    async def work(self, context: Context) -> AsyncIterator[Sequence[Completion]]:
        w_before, sw_before = lower(context.words_before), lower(context.syms_before)

        async def cached() -> LSPcomp:
            items = await self._use_cache(context)
            return LSPcomp(complete=False, items=items)

        async def stream() -> AsyncIterator[LSPcomp]:
            stream = request(
                self._supervisor.nvim,
                short_name=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                context=context,
            )
            for fut in as_completed(
                (cached(), anext(stream, LSPcomp(complete=False, items=iter(()))))
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

                if lsp_comps.complete and chunked:
                    await self._set_cache(context, completions=chunked)
                    yield ()

