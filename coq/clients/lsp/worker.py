from typing import Iterator, Sequence

from ...lsp.requests.completion import request
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context


class Worker(BaseWorker[BaseClient, None]):
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        use_cache, comps = request(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            tie_breaker=self._options.tie_breaker,
            context=context,
        )
        yield comps

