from typing import AsyncIterator

from pynvim_pp.lib import go

from ...databases.tmux.database import TMDB
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import WordbankClient
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, Edit
from ...tmux.parse import cur, snapshot


class Worker(BaseWorker[WordbankClient, TMDB]):
    def __init__(
        self, supervisor: Supervisor, options: WordbankClient, misc: TMDB
    ) -> None:
        super().__init__(supervisor, options=options, misc=misc)
        go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            with timeit("IDLE :: TMUX"):
                snap = await snapshot(self._supervisor.match.unifying_chars)
                await self._misc.periodical(snap)

            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        active = await cur()
        words = (
            await self._misc.select(
                self._supervisor.match,
                active_pane=active.uid,
                word=context.words,
                sym=(context.syms if self._options.match_syms else ""),
                limitless=context.manual,
            )
            if active
            else ()
        )

        for word in words:
            edit = Edit(new_text=word)
            cmp = Completion(
                source=self._options.short_name,
                weight_adjust=self._options.weight_adjust,
                label=edit.new_text,
                sort_by=word,
                primary_edit=edit,
                icon_match="Text",
            )
            yield cmp
