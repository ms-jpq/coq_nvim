from typing import Iterator, Sequence


from ...lsp.requests.completion import LUA, request
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import LSPClient
from ...shared.types import Completion, Context


class Worker(BaseWorker[LSPClient, None]):
    def __init__(self, supervisor: Supervisor, options: LSPClient, misc: None) -> None:
        supervisor.nvim.api.exec_lua(LUA, ())
        super().__init__(supervisor, options=options, misc=misc)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        yield from request(
            self._supervisor.nvim,
            short_name=self._options.short_name,
            tie_breaker=self._options.tie_breaker,
            protocol=self._options,
            context=context,
        )

