from typing import AsyncIterator

from ...lsp.requests.completion import request
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
        self._no_cache = False

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        w_before, sw_before = (
            lower(context.words_before),
            context.syms_before + lower(context.words_before),
        )
        if not self._no_cache:
            async for c in self._use_cache(context):
                yield c

        stream = request(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            tie_breaker=self._options.tie_breaker,
            context=context,
        )

        async for no_cache, comps in stream:
            self._no_cache = no_cache
            for c in comps:
                cword = (
                    w_before
                    if all(
                        is_word(
                            char,
                            unifying_chars=self._supervisor._options.unifying_chars,
                        )
                        for char in c.sort_by
                    )
                    else sw_before
                )
                go = (
                    quick_ratio(
                        cword,
                        lower(c.sort_by),
                        look_ahead=self._supervisor._options.look_ahead,
                    )
                    > self._supervisor._options.fuzzy_cutoff
                )
                if go:
                    yield c

            if not no_cache:
                await self._set_cache(context, completions=comps)

