from asyncio import gather
from dataclasses import dataclass
from shutil import which
from typing import AbstractSet, AsyncIterator, Optional, Sequence, Tuple

from pynvim_pp.lib import go
from std2.asyncio import call

from ...shared.parse import coalesce
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import WordbankClient
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, Edit
from .database import Database


@dataclass(frozen=True)
class _Pane:
    uid: str
    pane_active: bool
    window_active: bool


async def _panes() -> AsyncIterator[_Pane]:
    proc = await call(
        "tmux",
        "list-panes",
        "-s",
        "-F",
        "#{pane_id} #{pane_active} #{window_active}",
    )
    if proc.code:
        pass
    else:
        for line in proc.out.decode().strip().splitlines():
            pane_id, pane_active, window_active = line.split(" ")
            pane = _Pane(
                uid=pane_id,
                pane_active=bool(int(pane_active)),
                window_active=bool(int(window_active)),
            )
            yield pane


async def _cur() -> Optional[_Pane]:
    async for pane in _panes():
        if pane.window_active and pane.pane_active:
            return pane
    else:
        return None


async def _screenshot(
    unifying_chars: AbstractSet[str], uid: str
) -> Tuple[str, Sequence[str]]:
    proc = await call("tmux", "capture-pane", "-p", "-t", uid)
    if proc.code:
        return uid, ()
    else:
        words = tuple(coalesce(proc.out.decode(), unifying_chars=unifying_chars))
        return uid, words


class Worker(BaseWorker[WordbankClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: WordbankClient, misc: None
    ) -> None:
        self._tmux = which("tmux")
        self._db = Database(supervisor.pool)
        super().__init__(supervisor, options=options, misc=misc)
        if self._tmux:
            go(supervisor.nvim, aw=self._poll())

    async def _poll(self) -> None:
        while True:
            with timeit("IDLE :: TMUX"):
                shots = await gather(
                    *[
                        _screenshot(
                            self._supervisor.options.unifying_chars, uid=pane.uid
                        )
                        async for pane in _panes()
                    ]
                )
                snapshot = {uid: words for uid, words in shots}
                await self._db.periodical(snapshot)

            async with self._supervisor.idling:
                await self._supervisor.idling.wait()

    async def work(self, context: Context) -> AsyncIterator[Completion]:
        match = context.words or (context.syms if self._options.match_syms else "")
        active = await _cur() if self._tmux else None
        words = (
            await self._db.select(
                self._supervisor.options,
                active_pane=active.uid,
                word=match,
                limitless=context.manual,
            )
            if active
            else ()
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

