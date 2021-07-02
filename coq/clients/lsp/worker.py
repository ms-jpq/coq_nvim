from typing import Iterator, Sequence

from ...lsp.requests.completion import request
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context
from ..cache.worker import CacheWorker


class Worker(BaseWorker[BaseClient, None], CacheWorker):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        cached = self._use_cache(context)
        if cached:
            yield cached
        else:
            local_cache, comps = request(
                self._supervisor.nvim,
                short_name=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                context=context,
            )
            if local_cache:
                self._set_cache(context, completions=comps)
            else:
                self._set_cache(context, completions=())
            yield comps

