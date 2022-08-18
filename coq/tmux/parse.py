from asyncio import gather
from dataclasses import dataclass
from typing import AbstractSet, Iterator, Mapping, Optional, Sequence, Tuple

from pynvim_pp.lib import decode
from std2.asyncio.subprocess import call

from ..shared.parse import coalesce

_SEP = "\x1f"


@dataclass(frozen=True)
class Pane:
    session: str
    uid: str
    pane_active: bool
    window_active: bool

    session_name: str
    window_index: int
    window_name: str
    pane_index: int
    pane_title: str


async def _panes(all_sessions: bool) -> Sequence[Pane]:
    try:
        proc = await call(
            "tmux",
            "list-panes",
            ("-a" if all_sessions else "-s"),
            "-F",
            _SEP.join(
                (
                    "#{session_id}",
                    "#{pane_id}",
                    "#{pane_active}",
                    "#{window_active}",
                    "#{session_name}",
                    "#{window_index}",
                    "#{window_name}",
                    "#{pane_index}",
                    "#{pane_title}",
                )
            ),
            check_returncode=set(),
        )
    except OSError:
        return ()
    else:
        if proc.returncode:
            return ()
        else:

            def cont() -> Iterator[Pane]:
                for line in decode(proc.stdout).strip().splitlines():
                    (
                        session,
                        pane_id,
                        pane_active,
                        window_active,
                        session_name,
                        window_index,
                        window_name,
                        pane_index,
                        pane_title,
                    ) = line.split(_SEP)
                    pane = Pane(
                        session=session,
                        uid=pane_id,
                        pane_active=bool(int(pane_active)),
                        window_active=bool(int(window_active)),
                        session_name=session_name,
                        window_index=int(window_index),
                        window_name=window_name,
                        pane_index=int(pane_index),
                        pane_title=pane_title,
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
    pane: Pane,
) -> Tuple[Pane, Iterator[str]]:
    try:
        proc = await call(
            "tmux",
            "capture-pane",
            "-p",
            "-t",
            pane.uid,
            check_returncode=set(),
        )
    except OSError:
        return pane, iter(())
    else:
        if proc.returncode:
            return pane, iter(())
        else:
            words = coalesce(decode(proc.stdout), unifying_chars=unifying_chars)
            return pane, words


async def snapshot(
    all_sessions: bool, unifying_chars: AbstractSet[str]
) -> Tuple[Optional[str], Mapping[Pane, Iterator[str]]]:
    session, panes = await gather(_session(), _panes(all_sessions))
    shots = await gather(
        *(_screenshot(unifying_chars=unifying_chars, pane=pane) for pane in panes)
    )
    current = next(
        (
            pane
            for pane in panes
            if pane.session == session and pane.window_active and pane.pane_active
        ),
        None,
    )
    snapshot = {pane: words for pane, words in shots}
    return current.uid if current else None, snapshot
