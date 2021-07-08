from __future__ import annotations

from abc import abstractmethod
from asyncio import Condition, Task, gather, wait
from collections import Counter
from concurrent.futures import Executor
from dataclasses import dataclass
from typing import (
    Any,
    AsyncIterator,
    Generic,
    Mapping,
    MutableSequence,
    MutableSet,
    Protocol,
    Sequence,
    TypeVar,
    cast,
)
from uuid import UUID, uuid4
from weakref import WeakSet

from pynvim import Nvim
from pynvim_pp.lib import go

from .parse import coalesce
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

    def rate(
        self,
        batch: UUID,
        context: Context,
        neighbours: Mapping[str, int],
        completion: Completion,
    ) -> Metric:
        ...

    async def perf(
        self, worker: Worker, batch: UUID, duration: float, items: int
    ) -> None:
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

        go(cont())

    def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        async def cont() -> None:
            await gather(*(worker.notify(token, msg=msg) for worker in self._workers))

        go(cont())

    async def collect(self, context: Context, manual: bool) -> Sequence[Metric]:
        with l_timeit("COLLECTED -- **ALL**"):
            acc: MutableSequence[Metric] = []
            neighbours = Counter(
                word
                for line in context.lines
                for word in coalesce(line, unifying_chars=self.options.unifying_chars)
            )
            timeout = self._options.manual_timeout if manual else self._options.timeout

            async def supervise(worker: Worker) -> None:
                m_name = worker.__class__.__module__
                with l_timeit(f"COLLECTED -- {m_name}"):
                    batch, items = uuid4(), 0
                    await self._reviewer.perf(
                        worker, batch=batch, duration=0, items=items
                    )
                    async for completion in worker.work(context):
                        metric = self._reviewer.rate(
                            batch,
                            context=context,
                            neighbours=neighbours,
                            completion=completion,
                        )
                        acc.append(metric)

            task = cast(Task, go(gather(*map(supervise, self._workers))))
            await wait((task,), timeout=timeout)
            task.cancel()
            await task
            return acc


class Worker(Generic[O_co, T_co]):
    def __init__(self, supervisor: Supervisor, options: O_co, misc: T_co) -> None:
        self._supervisor, self._options, self._misc = supervisor, options, misc
        self._supervisor.register(self)

    async def notify(self, token: UUID, msg: Sequence[Any]) -> None:
        pass

    @abstractmethod
    def work(self, context: Context) -> AsyncIterator[Completion]:
        ...

