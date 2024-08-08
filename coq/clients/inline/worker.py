from typing import AsyncIterator

from ...lsp.requests.completion import comp_lsp_inline
from ...shared.executor import AsyncExecutor
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import LSPClient
from ...shared.types import Completion, Context


class Worker(BaseWorker[LSPClient, None]):
    def __init__(
        self,
        ex: AsyncExecutor,
        supervisor: Supervisor,
        options: LSPClient,
        misc: None,
    ) -> None:
        super().__init__(ex, supervisor=supervisor, options=options, misc=misc)

    def interrupt(self) -> None:
        with self._interrupt():
            pass

    async def _work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            async for comp in comp_lsp_inline(
                short_name=self._options.short_name,
                always_on_top=self._options.always_on_top,
                weight_adjust=self._options.weight_adjust,
                context=context,
                chunk=self._supervisor.match.max_results * 2,
                clients=set(),
            ):
                for row in comp.items:
                    yield row
