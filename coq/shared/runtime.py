from __future__ import annotations

from abc import abstractmethod
from collections import deque
from concurrent.futures import Future, InvalidStateError, ThreadPoolExecutor, wait
from contextlib import suppress
from threading import Lock
from typing import (
    Any,
    Deque,
    Generic,
    Iterator,
    MutableSequence,
    MutableSet,
    Sequence,
    TypeVar,
)
from uuid import UUID
from weakref import WeakSet

from pynvim import Nvim
from pynvim_pp.logging import log

from .settings import Options
from .types import Completion, Context

T_co = TypeVar("T_co", contravariant=True)
O_co = TypeVar("O_co", contravariant=True)


class Supervisor:
    def __init__(self, nvim: Nvim, pool: ThreadPoolExecutor, options: Options) -> None:
        self._nvim, self._pool, self._options = nvim, pool, options
        self._lock = Lock()
        self._workers: MutableSet[Worker] = WeakSet()
        self._futs: MutableSequence[Future] = []

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
        self._workers.add(worker)

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        for worker in self._workers:
            worker.notify(token, msg=msg)

    def collect(self, context: Context, manual: bool) -> Future:
        fut: Future = Future()
        acc: Deque[Completion] = deque()

        def supervise(worker: Worker) -> None:
            try:
                for completions in worker.work(context):
                    acc.extend(completions)
            except Exception as e:
                log.exception("%s", e)

        def cont() -> None:
            try:
                with self._lock:
                    for f in self._futs:
                        f.cancel()
                    self._futs.clear()
                    futs = tuple(
                        self._pool.submit(supervise, worker) for worker in self._workers
                    )
                    self._futs.extend(futs)
                timeout = None if manual else self._options.timeout
                wait(futs, timeout=timeout)
                with self._lock:
                    for f in self._futs:
                        f.cancel()

                with suppress(InvalidStateError):
                    fut.set_result(tuple(acc))
            except Exception as e:
                log.exception("%s", e)

        with self._lock:
            self._futs.append(self._pool.submit(cont))
        return fut


class Worker(Generic[O_co, T_co]):
    def __init__(self, supervisor: Supervisor, options: O_co, misc: T_co) -> None:
        self._supervisor, self._options, self._misc = supervisor, options, misc
        self._supervisor.register(self)

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        pass

    @abstractmethod
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        ...

