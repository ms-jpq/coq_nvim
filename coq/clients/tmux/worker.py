from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from shutil import which
from subprocess import CalledProcessError, check_output
from time import sleep
from typing import AbstractSet, Iterator, Mapping, Sequence, Tuple

from ...shared.parse import coalesce
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.types import Completion, Context, Edit


@dataclass(frozen=True)
class _Pane:
    uid: str
    pane_active: bool
    window_active: bool


def _panes() -> Sequence[_Pane]:
    try:
        out = check_output(
            (
                "tmux",
                "list-panes",
                "-s",
                "-F",
                "#{pane_id} #{pane_active} #{window_active}",
            ),
            text=True,
        )

    except CalledProcessError:
        return ()
    else:

        def cont() -> Iterator[_Pane]:
            for line in out.strip().splitlines():
                pane_id, pane_active, window_active = line.split(" ")
                pane = _Pane(
                    uid=pane_id,
                    pane_active=bool(int(pane_active)),
                    window_active=bool(int(window_active)),
                )
                yield pane

        return tuple(cont())


def _screenshot(unifying_chars: AbstractSet[str], uid: str) -> Sequence[str]:
    try:
        out = check_output(("tmux", "capture-pane", "-p", "-t", uid), text=True)
    except CalledProcessError:
        return ()
    else:
        return tuple(coalesce(out, unifying_chars=unifying_chars))


def _collect(
    pool: ThreadPoolExecutor, unifying_chars: AbstractSet[str]
) -> Mapping[_Pane, Sequence[str]]:
    def cont(pane: _Pane) -> Tuple[_Pane, Sequence[str]]:
        return pane, _screenshot(unifying_chars, uid=pane.uid)

    return {pane: words for pane, words in pool.map(cont, _panes())}


class Worker(BaseWorker[None]):
    def __init__(self, supervisor: Supervisor, misc: None) -> None:
        super().__init__(supervisor, misc=misc)

        self._panes: Mapping[_Pane, Sequence[str]] = {}
        if which("tmux"):
            supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        while True:
            self._panes = _collect(
                self._supervisor.pool,
                unifying_chars=self._supervisor.options.unifying_chars,
            )
            sleep(1)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        def cont() -> Iterator[Completion]:
            for pane, words in self._panes.items():
                if not (pane.window_active and pane.pane_active):
                    for word in words:
                        edit = Edit(new_text=word)
                        completion = Completion(primary_edit=edit)
                        yield completion

        yield tuple(cont())

