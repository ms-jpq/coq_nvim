from typing import AsyncIterator

from pynvim_pp.lib import go

from ...databases.treesitter.database import TDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import BaseClient
from ...shared.types import Completion, Context, Edit


class Worker(BaseWorker[BaseClient, TDB]):
    def __init__(self, supervisor: Supervisor, options: BaseClient, misc: TDB) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            pass

            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or context.syms
        words = await self._misc.select(
            self._supervisor.options, word=match, limitless=context.manual
        )

        for word, kind in words:
            edit = Edit(new_text=word)
            cmp = Completion(
                source=self._options.short_name,
                tie_breaker=self._options.tie_breaker,
                label=edit.new_text,
                sort_by=word,
                primary_edit=edit,
                kind=kind,
            )
            yield cmp
