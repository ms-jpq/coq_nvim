from asyncio import sleep
from random import uniform
from typing import AsyncIterator

from pynvim_pp.logging import suppress_and_log

from ...shared.executor import AsyncExecutor
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import LSPClient
from ...shared.timeit import timeit
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
        self._ex.run(self._poll())

    def interrupt(self) -> None:
        with self._interrupt():
            pass

    async def _poll(self) -> None:
        while True:

            async def cont() -> None:
                with suppress_and_log(), timeit("IDLE :: INLINE"):
                    await sleep(10)

            await self._with_interrupt(cont())
            async with self._idle:
                await self._idle.wait()

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
