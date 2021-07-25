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

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        w_before, sw_before = lower(context.words_before), lower(context.syms_before)

        stream = request(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            tie_breaker=self._options.tie_breaker,
            context=context,
        )

        async for c in self._use_cache(context):
            yield c
        async for no_cache, comps in stream:
            for c in comps:
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
                    > self._supervisor.options.fuzzy_cutoff
                )
                if go:
                    yield c

            if not no_cache:
                await self._set_cache(context, completions=comps)

