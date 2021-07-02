from __future__ import annotations

from abc import abstractmethod
from collections import Counter, deque
from concurrent.futures import Executor, Future, InvalidStateError, wait
from contextlib import suppress
from dataclasses import dataclass
from threading import Event, Lock
from typing import (
    Any,
    Deque,
    Generic,
    Iterator,
    Mapping,
    MutableSequence,
    MutableSet,
    Protocol,
    Sequence,
    TypeVar,
)
from uuid import UUID
from weakref import WeakSet

from pynvim import Nvim
from pynvim_pp.logging import log

from .parse import coalesce
from .settings import Options, Weights
from .timeit import timeit
from .types import Completion, Context

T_co = TypeVar("T_co", contravariant=True)
O_co = TypeVar("O_co", contravariant=True)


@dataclass(frozen=True)
class Metric:
    comp: Completion
    weight: Weights
    label_width: int


class PReviewer(Protocol):
    def rate(
        self,
        context: Context,
        neighbours: Mapping[str, int],
        completions: Sequence[Completion],
    ) -> Sequence[Metric]:
        ...


class Supervisor:
    def __init__(
        self,
        pool: Executor,
        nvim: Nvim,
        options: Options,
        reviewer: PReviewer,
    ) -> None:
        self._nvim, self._pool, self._options, self._reviewer = (
            nvim,
            pool,
            options,
            reviewer,
        )
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
    def pool(self) -> Executor:
        return self._pool

    def register(self, worker: Worker) -> None:
        self._workers.add(worker)

    def notify_idle(self) -> None:
        for worker in self._workers:
            worker.idling.set()

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        for worker in self._workers:
            worker.notify(token, msg=msg)

    def collect(self, context: Context, manual: bool) -> Future:
        with self._lock:
            for f in self._futs:
                f.cancel()
            self._futs.clear()

        future: Future = Future()
        acc: Deque[Metric] = deque()

        neighbours = Counter(
            word
            for line in context.lines
            for word in coalesce(line, unifying_chars=self.options.unifying_chars)
        )
        timeout = self._options.manual_timeout if manual else self._options.timeout

        def supervise(worker: Worker) -> None:
            try:
                m_name = worker.__class__.__module__
                with timeit(f"COLLECT -- {m_name}"):
                    for completions in worker.work(context):
                        metrics = self._reviewer.rate(
                            context, neighbours=neighbours, completions=completions
                        )
                        acc.extend(metrics)
            except Exception as e:
                log.exception("%s", e)

        def cont() -> None:
            try:
                futs = tuple(
                    self._pool.submit(supervise, worker) for worker in self._workers
                )
                with self._lock:
                    self._futs.extend(futs)
                wait(futs, timeout=timeout)

                with suppress(InvalidStateError):
                    future.set_result(tuple(acc))
            except Exception as e:
                log.exception("%s", e)

        f = self._pool.submit(cont)
        with self._lock:
            self._futs.append(f)

        return future


class Worker(Generic[O_co, T_co]):
    def __init__(self, supervisor: Supervisor, options: O_co, misc: T_co) -> None:
        self.idling = Event()
        self._supervisor, self._options, self._misc = supervisor, options, misc
        self._supervisor.register(self)
        self.idling.set()

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        pass

    @abstractmethod
    def work(self, context: Context) -> Iterator[Sequence[Completion]]:
        ...

