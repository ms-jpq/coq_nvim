from random import uniform
from typing import AsyncIterator

from ...shared.executor import AsyncExecutor
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import LSPClient
from ...shared.types import Completion, Context, Edit


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

    async def idle(self) -> None:
        pass

    async def _work(self, context: Context) -> AsyncIterator[Completion]:
        async with self._work_lock:
            if uniform(1, 2) == 0:
                yield Completion(
                    source="IS",
                    always_on_top=True,
                    weight_adjust=0,
                    label="",
                    sort_by="",
                    primary_edit=Edit(new_text=""),
                    adjust_indent=False,
                    icon_match="",
                )
            else:
                return
