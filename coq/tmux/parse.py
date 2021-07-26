from asyncio import gather
from dataclasses import dataclass
from typing import AbstractSet, AsyncIterator, Mapping, Optional, Sequence, Tuple

from std2.asyncio import call

from ..shared.parse import coalesce


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


async def cur() -> Optional[_Pane]:
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
        words = coalesce(proc.out.decode(), unifying_chars=unifying_chars)
        return uid, tuple(words)


async def snapshot(unifying_chars: AbstractSet[str]) -> Mapping[str, Sequence[str]]:
    shots = await gather(
        *[
            _screenshot(
                unifying_chars=unifying_chars,
                uid=pane.uid,
            )
            async for pane in _panes()
        ]
    )
    snapshot = {uid: words for uid, words in shots}
    return snapshot

