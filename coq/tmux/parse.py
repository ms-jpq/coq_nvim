from asyncio import gather
from dataclasses import dataclass
from typing import AbstractSet, Iterator, Mapping, Optional, Sequence, Tuple

from pynvim_pp.lib import decode
from std2.asyncio.subprocess import call

from ..shared.parse import coalesce


@dataclass(frozen=True)
class _Pane:
    session: str
    uid: str
    pane_active: bool
    window_active: bool


async def _panes(all_sessions: bool) -> Sequence[_Pane]:
    try:
        proc = await call(
            "tmux",
            "list-panes",
            ("-a" if all_sessions else "-s"),
            "-F",
            "#{session_id} #{pane_id} #{pane_active} #{window_active}",
            check_returncode=set(),
        )
    except OSError:
        return ()
    else:
        if proc.returncode:
            return ()
        else:

            def cont() -> Iterator[_Pane]:
                for line in decode(proc.stdout).strip().splitlines():
                    session, pane_id, pane_active, window_active = line.split(" ")
                    pane = _Pane(
                        session=session,
                        uid=pane_id,
                        pane_active=bool(int(pane_active)),
                        window_active=bool(int(window_active)),
                    )
                    yield pane

            return tuple(cont())


async def _session() -> Optional[str]:
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


async def _screenshot(
    unifying_chars: AbstractSet[str],
    uid: str,
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
    except OSError:
        return uid, iter(())
    else:
        if proc.returncode:
            return uid, iter(())
        else:
            words = coalesce(decode(proc.stdout), unifying_chars=unifying_chars)
            return uid, words


async def snapshot(
    all_sessions: bool, unifying_chars: AbstractSet[str]
) -> Tuple[Optional[str], Mapping[str, Iterator[str]]]:
    session, panes = await gather(_session(), _panes(all_sessions))
    shots = await gather(
        *(_screenshot(unifying_chars=unifying_chars, uid=pane.uid) for pane in panes)
    )
    current = next(
        (
            pane
            for pane in panes
            if pane.session == session and pane.window_active and pane.pane_active
        ),
        None,
    )
    snapshot = {uid: words for uid, words in shots}
    return current.uid if current else None, snapshot
