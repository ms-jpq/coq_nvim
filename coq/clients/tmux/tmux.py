from concurrent.futures import ThreadPoolExecutor
from time import sleep
from dataclasses import dataclass
from itertools import chain
from shutil import which
from subprocess import check_output
from typing import AbstractSet, Iterator, Sequence

from ...shared.parse import coalesce
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker


@dataclass(frozen=True)
class _Pane:
    session_id: str
    pane_id: str
    pane_active: bool
    window_active: bool


def _session() -> str:
    out = check_output(("tmux", "display-message", "-p", "#{session_id}"), text=True)
    return out.strip()


def _panes() -> Sequence[_Pane]:
    out = check_output(
        (
            "tmux",
            "list-panes",
            "-a",
            "-F",
            "#{session_id} #{pane_id} #{pane_active} #{window_active}",
        ),
        text=True,
    )

    def cont() -> Iterator[_Pane]:
        for line in out.strip().splitlines():
            session_id, pane_id, pane_active, window_active = line.split(" ")
            pane = _Pane(
                session_id=session_id,
                pane_id=pane_id,
                pane_active=bool(int(pane_active)),
                window_active=bool(int(window_active)),
            )
            yield pane

    return tuple(cont())


def _screenshot(unifying_chars: AbstractSet[str], pane: _Pane) -> Sequence[str]:
    out = check_output(("tmux", "capture-pane", "-p", "-t", pane.pane_id), text=True)
    return tuple(coalesce(out, unifying_chars=unifying_chars))


def _is_active(session_id: str, pane: _Pane) -> bool:
    return session_id == pane.session_id and pane.pane_active and pane.window_active


def _words(pool: ThreadPoolExecutor, unifying_chars: AbstractSet[str]) -> Sequence[str]:
    if which("tmux"):
        f1, f2 = pool.submit(_session), pool.submit(_panes)
        session_id, panes = f1.result(), f2.result()

        c1 = lambda pane: _screenshot(unifying_chars, pane=pane)
        it = pool.map(
            c1, (pane for pane in panes if not _is_active(session_id, pane=pane))
        )
        return tuple(chain.from_iterable(it))
    else:
        return ()


def _poll(pool: ThreadPoolExecutor, unifying_chars: AbstractSet[str]) -> None:
    while True:
        words = _words(pool, unifying_chars=unifying_chars)
        sleep(1)


class Worker(BaseWorker[None]):
    def __init__(self, supervisor: Supervisor, misc: None) -> None:
        super().__init__(supervisor, misc=misc)
        poll = lambda: _poll(
            supervisor.pool, unifying_chars=supervisor.options.unifying_chars
        )
        supervisor.pool.submit(poll)
