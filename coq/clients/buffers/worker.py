from typing import AsyncIterator

from pynvim_pp.api import list_bufs
from pynvim_pp.lib import async_call, go

from ...databases.buffers.database import BDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BuffersClient
from ...shared.types import Completion, Context, Edit


class Worker(BaseWorker[BuffersClient, BDB]):
    def __init__(
        self, supervisor: Supervisor, options: BuffersClient, misc: BDB
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            bufs = await async_call(
                self._supervisor.nvim, list_bufs, self._supervisor.nvim, listed=True
            )
            await self._misc.vacuum({buf.number for buf in bufs})
            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or (context.syms if self._options.match_syms else "")
        filetype = context.filetype if self._options.same_filetype else None
        words = await self._misc.words(
            self._supervisor.options,
            filetype=filetype,
            word=match,
            limitless=context.manual,
        )
        for word in words:
            edit = Edit(new_text=word)
            cmp = Completion(
                source=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                label=edit.new_text,
                sort_by=word,
                primary_edit=edit,
            )
            yield cmp
