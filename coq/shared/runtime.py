from __future__ import annotations

from abc import abstractmethod
from asyncio import (
    AbstractEventLoop,
    Condition,
    Lock,
    Task,
    as_completed,
    gather,
    sleep,
    wait,
)
from concurrent.futures import Executor
from dataclasses import dataclass
from itertools import chain
from time import monotonic
from typing import (
    AbstractSet,
    AsyncIterator,
    Awaitable,
    Generic,
    MutableMapping,
    MutableSequence,
    Optional,
    Protocol,
    Sequence,
    TypeVar,
)
from uuid import UUID, uuid4
from weakref import WeakKeyDictionary

from pynvim import Nvim
from pynvim_pp.lib import go
from pynvim_pp.logging import with_suppress
from std2.asyncio import cancel

from .settings import BaseClient, Limits, Options, Weights
from .timeit import timeit
from .types import Completion, Context

T_co = TypeVar("T_co", contravariant=True)
O_co = TypeVar("O_co", contravariant=True, bound=BaseClient)


@dataclass(frozen=True)
class Metric:
    instance: UUID
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
        self.pool = pool
        self.options, self.limits = options, limits
        self.nvim, self._reviewer = nvim, reviewer

        self.idling = Condition()
        self._workers: MutableMapping[Worker, BaseClient] = WeakKeyDictionary()

        self._lock = Lock()
        self._task: Optional[Task] = None
        self._tasks: Sequence[Task] = ()

    @property
    def clients(self) -> AbstractSet[BaseClient]:
        return {*self._workers.values()}

    def register(self, worker: Worker, assoc: BaseClient) -> None:
        self._reviewer.register(assoc)
        self._workers[worker] = assoc

    def notify_idle(self) -> None:
        async def cont() -> None:
            async with self.idling:
                self.idling.notify_all()

        go(self.nvim, aw=cont())

    async def interrupt(self) -> None:
        with timeit("INTERRUPTED -- ALL"):
            g = gather(*chain(((self._task,) if self._task else ()), self._tasks))
            self._task, self._tasks = None, ()
            await cancel(g)

    def collect(self, context: Context) -> Awaitable[Sequence[Metric]]:
        loop: AbstractEventLoop = self.nvim.loop
        t1, done = monotonic(), False
        timeout = (
            self.limits.completion_manual_timeout
            if context.manual
            else self.limits.completion_auto_timeout
        )

        acc: MutableSequence[Metric] = []

        async def supervise(worker: Worker, assoc: BaseClient) -> None:
            instance, items = uuid4(), 0

            with with_suppress(), timeit(f"WORKER -- {assoc.short_name}"):
                await self._reviewer.s_begin(assoc, instance=instance)
                try:
                    async for completion in worker.work(context):
                        if not done and completion:
                            metric = self._reviewer.trans(
                                instance, completion=completion
                            )
                            acc.append(metric)
                            items += 1
                        else:
                            await sleep(0)
                finally:
                    elapsed = monotonic() - t1
                    await self._reviewer.s_end(
                        instance,
                        interrupted=done,
                        elapsed=elapsed,
                        items=items,
                    )

        async def cont() -> Sequence[Metric]:
            with with_suppress(), timeit("COLLECTED -- **ALL**"):
                assert not self._lock.locked()
                async with self._lock:
                    await self._reviewer.begin(context)
                    self._tasks = tasks = tuple(
                        loop.create_task(supervise(worker, assoc=assoc))
                        for worker, assoc in self._workers.items()
                    )
                    try:
                        if not tasks:
                            return ()
                        else:
                            _, pending = await wait(tasks, timeout=timeout)
                            if not acc:
                                for fut in as_completed(pending):
                                    await fut
                                    if acc:
                                        break
                            return acc
                    finally:
                        done = True

        self._task = loop.create_task(cont())
        return self._task


class Worker(Generic[O_co, T_co]):
    def __init__(self, supervisor: Supervisor, options: O_co, misc: T_co) -> None:
        self._supervisor, self._options, self._misc = supervisor, options, misc
        self._supervisor.register(self, assoc=options)

    @abstractmethod
    def work(self, context: Context) -> AsyncIterator[Optional[Completion]]:
        ...
