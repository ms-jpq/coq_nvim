from asyncio import gather
from dataclasses import dataclass
from typing import AbstractSet, Iterator, Mapping, Optional, Tuple

from pynvim_pp.lib import decode
from std2.asyncio.subprocess import call

from ..shared.parse import coalesce


@dataclass(frozen=True)
class _Pane:
    session: str
    pane: str
    pane_active: bool
    window_active: bool

    @property
    def uid(self) -> str:
        return f"{self.session}{self.pane}"


async def _panes() -> Iterator[_Pane]:
    try:
        proc = await call(
            "tmux",
            "list-panes",
            "-a",
            "-F",
            "#{session_id} #{pane_id} #{pane_active} #{window_active}",
            check_returncode=set(),
        )
    except OSError:
        return iter(())
    else:
        if proc.returncode:
            return iter(())
        else:

            def cont() -> Iterator[_Pane]:
                for line in decode(proc.stdout).strip().splitlines():
                    session, pane, pane_active, window_active = line.split(" ")
                    pane = _Pane(
                        session=session,
                        pane=pane,
                        pane_active=bool(int(pane_active)),
                        window_active=bool(int(window_active)),
                    )
                    yield pane

            return cont()


async def cur() -> Optional[_Pane]:
    async def cont() -> Optional[str]:
        try:
            proc = await call(
                "tmux", "display-message", "-p", "#{session_id}", check_returncode=set()
            )
        except OSError:
            return None
        else:
            if proc.returncode:
                return None
            else:
                session = decode(proc.stdout).strip()
                return session

    session, panes = await gather(cont(), _panes())
    for pane in panes:
        if pane.session == session and pane.window_active and pane.pane_active:
            return pane
    else:
        return None


async def _screenshot(
    unifying_chars: AbstractSet[str],
    pane: _Pane,
) -> Tuple[str, Iterator[str]]:
    try:
        proc = await call(
            "tmux",
            "capture-pane",
            "-p",
            "-t",
            pane.pane,
            check_returncode=set(),
        )
    except OSError:
        return pane.uid, iter(())
    else:
        if proc.returncode:
            return pane.uid, iter(())
        else:
            words = coalesce(decode(proc.stdout), unifying_chars=unifying_chars)
            return pane.uid, words


async def snapshot(unifying_chars: AbstractSet[str]) -> Mapping[str, Iterator[str]]:
    shots = await gather(
        *(
            _screenshot(unifying_chars=unifying_chars, pane=pane)
            for pane in await _panes()
        )
    )
    print(shots, flush=True)
    snapshot = {uid: words for uid, words in shots}
    return snapshot
