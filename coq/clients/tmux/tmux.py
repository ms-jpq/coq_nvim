from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from shutil import which
from subprocess import CalledProcessError, check_output
from time import sleep
from typing import AbstractSet, Iterator, Mapping, Optional, Sequence, Tuple
from uuid import UUID

from ...shared.parse import coalesce
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, Edit


@dataclass(frozen=True)
class _Pane:
    session_id: str
    pane_id: str
    pane_active: bool
    window_active: bool


def _session() -> Optional[str]:
    try:
        out = check_output(
            ("tmux", "display-message", "-p", "#{session_id}"), text=True
        )
    except CalledProcessError:
        return None
    else:
        return out.strip()


def _panes() -> Sequence[_Pane]:
    try:
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

    except CalledProcessError:
        return ()
    else:

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
    try:
        out = check_output(
            ("tmux", "capture-pane", "-p", "-t", pane.pane_id), text=True
        )
    except CalledProcessError:
        return ()
    else:
        return tuple(coalesce(out, unifying_chars=unifying_chars))


def _collect(
    pool: ThreadPoolExecutor, unifying_chars: AbstractSet[str], session_id: str
) -> Mapping[_Pane, Sequence[str]]:
    panes = (pane for pane in _panes() if pane.session_id == session_id)
    cont = lambda pane: (pane, _screenshot(unifying_chars, pane=pane))
    return {pane: words for pane, words in pool.map(cont, panes)}


class Worker(BaseWorker[None]):
    def __init__(self, supervisor: Supervisor, misc: None) -> None:
        super().__init__(supervisor, misc=misc)

        self._panes: Mapping[_Pane, Sequence[str]] = {}
        if which("tmux"):
            self._session = _session()
            supervisor.pool.submit(self._poll)
        else:
            self._session = None

    def _poll(self) -> None:
        while self._session:
            self._panes = _collect(
                self._supervisor.pool,
                unifying_chars=self._supervisor.options.unifying_chars,
                session_id=self._session,
            )
            sleep(1)

    def work(self, token: UUID, context: Context) -> Tuple[UUID, Sequence[Completion]]:
        def cont() -> Iterator[Completion]:
            for pane, words in self._panes.items():
                if not (pane.window_active and pane.pane_active):
                    for word in words:
                        edit = Edit(new_text=word)
                        completion = Completion(
                            position=context.position, primary_edit=edit
                        )
                        yield completion

        return token, tuple(cont())
