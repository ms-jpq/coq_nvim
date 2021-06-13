from __future__ import annotations

from abc import abstractmethod
from collections import deque
from concurrent.futures import (
    Future,
    InvalidStateError,
    ThreadPoolExecutor,
    TimeoutError,
    as_completed,
)
from contextlib import suppress
from typing import Deque, Generic, Iterator, MutableSet, Sequence, TypeVar
from uuid import UUID
from weakref import WeakSet

from pynvim import Nvim
from pynvim_pp.logging import log

from .settings import Options
from .types import Completion, Context

T_co = TypeVar("T_co", contravariant=True)


class Supervisor:
    def __init__(self, nvim: Nvim, pool: ThreadPoolExecutor, options: Options) -> None:
        self._nvim, self._pool, self._options = nvim, pool, options
        self._workers: MutableSet[Worker] = WeakSet()

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

    def notify(self, token: UUID, msg: Sequence[str]) -> None:
        for worker in self._workers:
            worker.notify(token, msg=msg)

    def collect(self, context: Context) -> Future:
        fut: Future = Future()
        acc: Deque[Completion] = deque()

        def supervise(worker: Worker) -> None:
            for completions in worker.work(context):
                acc.extend(completions)

        def cont() -> None:
            try:
                futs = tuple(
                    self._pool.submit(supervise, worker) for worker in self._workers
                )
                for f in as_completed(futs, timeout=self._options.timeout):
                    try:
                        f.result()
                    except Exception as e:
                        log.exception("%s", e)

                with suppress(InvalidStateError):
                    fut.set_result(tuple(acc))
            except TimeoutError:
                pass

        self._pool.submit(cont)
        return fut


class Worker(Generic[T_co]):
    def __init__(self, supervisor: Supervisor, misc: T_co) -> None:
        self._supervisor, self._misc = supervisor, misc
        self._supervisor.register(self)

    @abstractmethod
    def notify(self, token: UUID, msg: Sequence[str]) -> None:
        ...

    @abstractmethod
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        ...

