from __future__ import annotations

from abc import abstractmethod
from asyncio import Condition, gather, wait
from asyncio.tasks import sleep
from concurrent.futures import Executor
from dataclasses import dataclass
from typing import (
    AsyncIterator,
    Generic,
    MutableSequence,
    MutableSet,
    Optional,
    Protocol,
    Sequence,
    TypeVar,
)
from uuid import UUID, uuid4
from weakref import WeakSet

from pynvim import Nvim
from pynvim_pp.lib import go
from std2.aitertools import aenumerate
from std2.timeit import timeit

from .settings import Options, Weights
from .timeit import timeit as l_timeit
from .types import Completion, Context

T_co = TypeVar("T_co", contravariant=True)
O_co = TypeVar("O_co", contravariant=True)


@dataclass(frozen=True)
class Metric:
    batch: UUID
    comp: Completion
    weight: Weights
    label_width: int
    kind_width: int


class PReviewer(Protocol):
    def register(self, worker: Worker) -> None:
        ...

    async def begin(self, context: Context) -> None:
        ...

    async def s1(self, worker: Worker, batch: UUID) -> None:
        ...

    def s2(self, batch: UUID, completion: Completion) -> Metric:
        ...

    async def end(self, elapsed: Optional[float], items: Optional[int]) -> None:
        ...


class Supervisor:
    def __init__(
        self,
        pool: Executor,
        nvim: Nvim,
        options: Options,
        reviewer: PReviewer,
    ) -> None:
        self._pool, self._nvim, self._options, self._reviewer = (
            pool,
            nvim,
            options,
            reviewer,
        )
        self._idling = Condition()
        self._workers: MutableSet[Worker] = WeakSet()

    @property
    def pool(self) -> Executor:
        return self._pool

    @property
    def idling(self) -> Condition:
        return self._idling

    @property
    def nvim(self) -> Nvim:
        return self._nvim

    @property
    def options(self) -> Options:
        return self._options

    def register(self, worker: Worker) -> None:
        self._reviewer.register(worker)
        self._workers.add(worker)

    def notify_idle(self) -> None:
        async def cont() -> None:
            async with self._idling:
                self._idling.notify_all()

        go(self.nvim, aw=cont())

    async def collect(self, context: Context, manual: bool) -> Sequence[Metric]:
        with l_timeit("COLLECTED -- **ALL**"):
            acc: MutableSequence[Metric] = []
            timeout = self._options.manual_timeout if manual else self._options.timeout

            async def supervise(worker: Worker) -> None:
                m_name, batch = worker.__class__.__module__, uuid4()
                with l_timeit(f"COLLECTED -- {m_name}"):
                    await self._reviewer.s1(worker, batch=batch)
                    elapsed, items = None, None
                    try:
                        with timeit() as t:
                            async for items, completion in aenumerate(
                                worker.work(context), start=1
                            ):
                                metric = self._reviewer.s2(batch, completion=completion)
                                acc.append(metric)
                        elapsed = t()
                    finally:
                        await self._reviewer.end(elapsed, items=items)

            await self._reviewer.begin(context)
            task = gather(*map(supervise, self._workers))
            await wait((task,), timeout=timeout)
            return acc


class Worker(Generic[O_co, T_co]):
    def __init__(self, supervisor: Supervisor, options: O_co, misc: T_co) -> None:
        self._supervisor, self._options, self._misc = supervisor, options, misc
        self._supervisor.register(self)

    @abstractmethod
    def work(self, context: Context) -> AsyncIterator[Completion]:
        ...

