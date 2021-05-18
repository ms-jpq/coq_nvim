from concurrent.futures import ThreadPoolExecutor
from threading import Lock
from typing import Iterable, MutableSequence, Sequence
from uuid import UUID, uuid4

from pynvim import Nvim

from ..agnostic.datatypes import Completion
from ..agnostic.rttypes import Supervisor
from ..agnostic.settings.types import Options


class Super(Supervisor):
    def __init__(self, nvim: Nvim, pool: ThreadPoolExecutor, options: Options) -> None:
        self._nvim, self._pool, self._options = nvim, pool, options

        self._lock = Lock()

        self._token = uuid4()
        self._completions: MutableSequence[Completion] = []

    def options(self) -> Options:
        return self._options

    def nvim(self) -> Nvim:
        return self._nvim

    def pool(self) -> ThreadPoolExecutor:
        return self._pool

    def add(self, token: UUID, completions: Iterable[Completion]) -> None:
        with self._lock:
            if token != self._token:
                pass
            else:
                self._completions.extend(completions)

    def report(self) -> Sequence[Completion]:
        with self._lock:
            completions = self._completions
            self._completions = []
            self._token = uuid4()
            return completions
