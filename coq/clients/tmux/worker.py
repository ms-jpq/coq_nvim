from dataclasses import dataclass
from shutil import which
from subprocess import DEVNULL, CalledProcessError, TimeoutExpired, check_output
from time import sleep
from typing import AbstractSet, Iterator, Optional, Sequence, Tuple

from pynvim_pp.logging import log

from ...consts import TIMEOUT
from ...shared.parse import coalesce
from ...shared.runtime import Supervisor
from ...shared.runtime import Worker as BaseWorker
from ...shared.settings import WordbankClient
from ...shared.types import Completion, Context, Edit
from .database import Database


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
            timeout=TIMEOUT,
            stdin=DEVNULL,
            stderr=DEVNULL,
        )

    except (CalledProcessError, TimeoutExpired):
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


def _cur() -> Optional[_Pane]:
    for pane in _panes():
        if pane.window_active and pane.pane_active:
            return pane
    else:
        return None


def _screenshot(unifying_chars: AbstractSet[str], uid: str) -> Sequence[str]:
    try:
        out = check_output(
            ("tmux", "capture-pane", "-p", "-t", uid),
            text=True,
            timeout=TIMEOUT,
            stdin=DEVNULL,
            stderr=DEVNULL,
        )
    except (CalledProcessError, TimeoutExpired):
        return ()
    else:
        return tuple(coalesce(out, unifying_chars=unifying_chars))


class Worker(BaseWorker[WordbankClient, None]):
    def __init__(
        self, supervisor: Supervisor, options: WordbankClient, misc: None
    ) -> None:
        self._db = Database(supervisor.pool)
        super().__init__(supervisor, options=options, misc=misc)
        if which("tmux"):
            supervisor.pool.submit(self._poll)

    def _poll(self) -> None:
        try:

            def cont(pane: _Pane) -> Tuple[_Pane, Sequence[str]]:
                words = _screenshot(
                    self._supervisor.options.unifying_chars, uid=pane.uid
                )
                return pane, words

            while True:
                snapshot = {
                    pane.uid: words
                    for pane, words in self._supervisor.pool.map(cont, _panes())
                }
                self._db.periodical(snapshot)
                sleep(self._options.polling_interval)
        except Exception as e:
            log.exception("%s", e)

    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        match = context.words or (context.syms if self._options.match_syms else "")
        active = _cur()
        words = (
            self._db.select(
                self._supervisor.options,
                active_pane=active.uid,
                word=match,
            )
            if active
            else ()
        )

        def cont() -> Iterator[Completion]:
            for word in words:
                edit = Edit(new_text=word)
                cmp = Completion(
                    source=self._options.short_name,
                    tie_breaker=self._options.tie_breaker,
                    label=edit.new_text,
                    primary_edit=edit,
                )
                yield cmp

        yield tuple(cont())

