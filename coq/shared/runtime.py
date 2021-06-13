from __future__ import annotations

from abc import abstractmethod
from concurrent.futures import FIRST_EXCEPTION, ThreadPoolExecutor, TimeoutError, wait
from threading import Lock
from typing import Generic, Iterator, MutableSequence, MutableSet, Sequence, TypeVar
from weakref import WeakSet

from pynvim import Nvim

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

    def work(self, context: Context) -> Sequence[Completion]:
        lock, timed_out = Lock(), False
        acc: MutableSequence[Completion] = []

        def supervise(worker: Worker) -> None:
            for completion in worker.work(context):
                with lock:
                    if timed_out:
                        break
                    else:
                        acc.append(completion)

        futs = (self._pool.submit(supervise, worker) for worker in self._workers)
        try:
            wait(futs, return_when=FIRST_EXCEPTION, timeout=self._options.timeout)
        except TimeoutError:
            with lock:
                timed_out = True
                return tuple(acc)
        else:
            with lock:
                return tuple(acc)


class Worker(Generic[T_co]):
    def __init__(self, supervisor: Supervisor, misc: T_co) -> None:
        self._supervisor, self._misc = supervisor, misc
        self._supervisor.register(self)

    @abstractmethod
    def work(self, context: Context) -> Iterator[Completion]:
        ...
