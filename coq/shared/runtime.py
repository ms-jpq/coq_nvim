from __future__ import annotations

from abc import abstractmethod
from concurrent.futures import ThreadPoolExecutor
from threading import Lock
from typing import Generic, MutableSequence, Sequence, Tuple, TypeVar
from uuid import UUID, uuid4
from weakref import WeakSet

from pynvim import Nvim
from pynvim_pp.logging import log

from .settings import Options
from .types import Completion, Context

T_co = TypeVar("T_co", contravariant=True)


class Supervisor:
    def __init__(self, nvim: Nvim, pool: ThreadPoolExecutor, options: Options) -> None:
        self._nvim, self._pool, self._options = nvim, pool, options

        self._lock = Lock()
        self._workers = WeakSet()

        self._token = uuid4()
        self._completions: MutableSequence[Completion] = []

    @property
    def options(self) -> Options:
        return self._options

    @property
    def nvim(self) -> Nvim:
        return self._nvim

    @property
    def pool(self) -> ThreadPoolExecutor:
        return self._pool

    def register(self, worker: Worker) -> None:
        with self._lock:
            self._workers.add(worker)

    def _report(self, token: UUID, completions: Sequence[Completion]) -> None:
        with self._lock:
            if token != self._token:
                pass
            else:
                self._completions.extend(completions)

    def notify(self, context: Context) -> None:
        with self._lock:
            assert not self._completions

            for worker in self._workers:

                def cont() -> None:
                    try:
                        token, completions = worker.work(self._token, context=context)
                    except Exception as e:
                        log.exception("%s", e)
                    else:
                        self._report(token, completions)

                self._pool.submit(cont)

    def collect(self) -> Sequence[Completion]:
        with self._lock:
            completions = self._completions
            self._completions = []
            self._token = uuid4()
            return completions


class Worker(Generic[T_co]):
    def __init__(self, supervisor: Supervisor, misc: T_co) -> None:
        self._supervisor, self._misc = supervisor, misc
        self._supervisor.register(self)

    @abstractmethod
    def work(self, token: UUID, context: Context) -> Tuple[UUID, Sequence[Completion]]:
        ...
