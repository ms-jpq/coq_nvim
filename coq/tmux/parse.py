from asyncio import gather
from dataclasses import dataclass
from typing import AbstractSet, Iterator, Mapping, Optional, Tuple

from std2.asyncio.subprocess import call

from ..shared.parse import coalesce


@dataclass(frozen=True)
class _Pane:
    uid: str
    pane_active: bool
    window_active: bool


async def _panes() -> Iterator[_Pane]:
    try:
        proc = await call(
            "tmux",
            "list-panes",
            "-s",
            "-F",
            "#{pane_id} #{pane_active} #{window_active}",
            check_returncode=set(),
        )
    except FileNotFoundError:
        return iter(())
    else:
        if proc.code:
            return iter(())
        else:

            def cont() -> Iterator[_Pane]:
                for line in proc.out.decode().strip().splitlines():
                    pane_id, pane_active, window_active = line.split(" ")
                    pane = _Pane(
                        uid=pane_id,
                        pane_active=bool(int(pane_active)),
                        window_active=bool(int(window_active)),
                    )
                    yield pane

            return cont()


async def cur() -> Optional[_Pane]:
    for pane in await _panes():
        if pane.window_active and pane.pane_active:
            return pane
    else:
        return None


async def _screenshot(
    unifying_chars: AbstractSet[str], uid: str
) -> Tuple[str, Iterator[str]]:
    try:
        proc = await call(
            "tmux",
            "capture-pane",
            "-p",
            "-t",
            uid,
            check_returncode=set(),
        )
    except FileNotFoundError:
        return uid, iter(())
    else:
        if proc.code:
            return uid, iter(())
        else:
            words = coalesce(proc.out.decode(), unifying_chars=unifying_chars)
            return uid, words


async def snapshot(unifying_chars: AbstractSet[str]) -> Mapping[str, Iterator[str]]:
    shots = await gather(
        *(
            _screenshot(
                unifying_chars=unifying_chars,
                uid=pane.uid,
            )
            for pane in await _panes()
        )
    )
    snapshot = {uid: words for uid, words in shots}
    return snapshot
