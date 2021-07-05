from typing import Iterator, Sequence

from ...lsp.requests.completion import request
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context
from ..cache.worker import CacheWorker


class Worker(BaseWorker[BaseClient, None], CacheWorker):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: None) -> None:
        CacheWorker.__init__(self, supervisor=supervisor)
        BaseWorker.__init__(self, supervisor=supervisor, options=options, misc=misc)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        cached = self._use_cache(context)
        if cached is not None:
            yield cached
        else:
            stream = request(
                self._supervisor.nvim,
                short_name=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                context=context,
            )
            for local_cache, comps in stream:
                yield comps
                if local_cache:
                    self._set_cache(context, completions=comps)
                else:
                    self._set_cache(context, completions=())
                yield ()
                if comps:
                    break

