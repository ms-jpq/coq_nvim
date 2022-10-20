from asyncio import gather
from dataclasses import dataclass
from functools import lru_cache
from os import environ
from pathlib import Path
from typing import Iterator, Mapping, Optional, Sequence, Tuple

from pynvim_pp.lib import decode
from std2.asyncio.subprocess import call

_SEP = "\x1f"


@dataclass(frozen=True)
class Pane:
    session: str
    uid: str

    session_name: str
    window_index: int
    window_name: str
    pane_index: int
    pane_title: str


async def _panes(tmux: Path, all_sessions: bool) -> Sequence[Pane]:
    try:
        proc = await call(
            tmux,
            "list-panes",
            ("-a" if all_sessions else "-s"),
            "-F",
            _SEP.join(
                (
                    "#{session_id}",
                    "#{pane_id}",
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
                        session_name,
                        window_index,
                        window_name,
                        pane_index,
                        pane_title,
                    ) = line.split(_SEP)
                    pane = Pane(
                        session=session,
                        uid=pane_id,
                        session_name=session_name,
                        window_index=int(window_index),
                        window_name=window_name,
                        pane_index=int(pane_index),
                        pane_title=pane_title,
                    )
                    yield pane

            return tuple(cont())


async def _screenshot(pane: Pane) -> Tuple[Pane, str]:
    try:
        proc = await call(
            "tmux",
            "capture-pane",
            "-p",
            "-J",
            "-t",
            pane.uid,
            check_returncode=set(),
        )
    except OSError:
        return pane, ""
    else:
        if proc.returncode:
            return pane, ""
        else:
            text = decode(proc.stdout)
            return pane, text


@lru_cache(maxsize=None)
def pane_id() -> Optional[str]:
    return environ.get("TMUX_PANE")


async def snapshot(
    tmux: Path, all_sessions: bool
) -> Tuple[Optional[Pane], Mapping[Pane, str]]:
    panes = await _panes(tmux, all_sessions=all_sessions)
    shots = await gather(*map(_screenshot, panes))
    current = next(
        (pane for pane in panes if pane.uid == pane_id()),
        None,
    )
    snapshot = {pane: text for pane, text in shots}
    return current, snapshot
