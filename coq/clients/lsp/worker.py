from threading import Lock
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
        self._lock, self._only_use_cached = Lock(), False

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        with self._lock:
            only_use_cached = self._only_use_cached

        cached = self._use_cache(context)
        if cached:
            yield cached

        if only_use_cached and cached is not None:
            pass
        else:
            stream = request(
                self._supervisor.nvim,
                short_name=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                context=context,
            )

            for only_use_cached, comps in stream:
                with self._lock:
                    self._only_use_cached = only_use_cached
                yield comps
                self._set_cache(context, completions=comps)
                yield ()

