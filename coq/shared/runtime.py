from __future__ import annotations

from abc import abstractmethod
from asyncio import Condition, Lock, Task, as_completed, gather, wait
from concurrent.futures import Executor
from dataclasses import dataclass
from time import monotonic
from typing import (
    AbstractSet,
    AsyncIterator,
    Generic,
    MutableMapping,
    MutableSequence,
    Protocol,
    Sequence,
    TypeVar,
    cast,
)
from uuid import UUID, uuid4
from weakref import WeakKeyDictionary

from pynvim import Nvim
from pynvim_pp.lib import go
from std2.aitertools import aenumerate
from std2.asyncio import cancel

from .settings import BaseClient, Limits, Options, Weights
from .timeit import timeit
from .types import Completion, Context

T_co = TypeVar("T_co", contravariant=True)
O_co = TypeVar("O_co", contravariant=True, bound=BaseClient)


@dataclass(frozen=True)
class Metric:
    istance: UUID
    comp: Completion
    weight: Weights
    label_width: int
    kind_width: int


class PReviewer(Protocol):
    def register(self, assoc: BaseClient) -> None:
        ...

    async def begin(self, context: Context) -> None:
        ...

    async def s_begin(self, assoc: BaseClient, instance: UUID) -> None:
        ...

    def trans(self, instance: UUID, completion: Completion) -> Metric:
        ...

    async def s_end(
        self, instance: UUID, interrupted: bool, elapsed: float, items: int
    ) -> None:
        ...


class Supervisor:
    def __init__(
        self,
        pool: Executor,
        nvim: Nvim,
        options: Options,
        limits: Limits,
        reviewer: PReviewer,
    ) -> None:
        self._pool, self._nvim, self._options, self._limits, self._reviewer = (
            pool,
            nvim,
            options,
            limits,
            reviewer,
        )
        self._lock = Lock()
        self._idling = Condition()
        self._workers: MutableMapping[Worker, BaseClient] = WeakKeyDictionary()
        self._tasks: Sequence[Task] = ()

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
    def clients(self) -> AbstractSet[BaseClient]:
        return {*self._workers.values()}

    @property
    def options(self) -> Options:
        return self._options

    def register(self, worker: Worker, assoc: BaseClient) -> None:
        self._reviewer.register(assoc)
        self._workers[worker] = assoc

    def notify_idle(self) -> None:
        async def cont() -> None:
            async with self._idling:
                self._idling.notify_all()

        go(self.nvim, aw=cont())

    async def interrupt(self) -> None:
        await cancel(gather(*self._tasks))
        self._tasks = ()

    async def collect(self, context: Context) -> Sequence[Metric]:
        with timeit("COLLECTED -- **ALL**"):
            assert not self._lock.locked()
            async with self._lock:
                acc: MutableSequence[Metric] = []
                timeout = (
                    self._limits.manual_timeout
                    if context.manual
                    else self._limits.timeout
                )

                async def supervise(worker: Worker, assoc: BaseClient) -> None:
                    with timeit(f"WORKER -- {assoc.short_name}"):
                        instance, t1 = uuid4(), monotonic()
                        interrupted, items = True, 0
                        try:
                            await self._reviewer.s_begin(assoc, instance=instance)
                            async for items, completion in aenumerate(
                                worker.work(context), start=1
                            ):
                                metric = self._reviewer.trans(
                                    instance, completion=completion
                                )
                                acc.append(metric)
                            else:
                                interrupted = False
                        finally:
                            elapsed = monotonic() - t1
                            await self._reviewer.s_end(
                                instance,
                                interrupted=interrupted,
                                elapsed=elapsed,
                                items=items,
                            )

                await self._reviewer.begin(context)
                self._tasks = tuple(
                    cast(Task, go(self.nvim, aw=supervise(worker, assoc=assoc)))
                    for worker, assoc in self._workers.items()
                )
                if not self._tasks:
                    return ()
                else:
                    _, pending = await wait(self._tasks, timeout=timeout)
                    if not acc:
                        for fut in as_completed(pending):
                            await fut
                            if acc:
                                break
                    return acc


class Worker(Generic[O_co, T_co]):
    def __init__(self, supervisor: Supervisor, options: O_co, misc: T_co) -> None:
        self._supervisor, self._options, self._misc = supervisor, options, misc
        self._supervisor.register(self, assoc=options)

    @abstractmethod
    def work(self, context: Context) -> AsyncIterator[Completion]:
        ...

