from __future__ import annotations

from abc import abstractmethod
from asyncio import CancelledError, Condition, Task, as_completed, create_task, wait
from dataclasses import dataclass
from pathlib import Path
from time import monotonic
from typing import (
    Any,
    AsyncIterator,
    Awaitable,
    Generic,
    MutableSequence,
    Optional,
    Protocol,
    Sequence,
    TypeVar,
)
from uuid import UUID, uuid4
from weakref import WeakSet

from pynvim_pp.logging import suppress_and_log
from std2.aitertools import aenumerate
from std2.asyncio import cancel

from .settings import (
    BaseClient,
    CompleteOptions,
    Display,
    Limits,
    MatchOptions,
    Weights,
)
from .timeit import TracingLocker, timeit
from .types import Completion, Context

_T = TypeVar("_T")
_T_co = TypeVar("_T_co", contravariant=True)
_O_co = TypeVar("_O_co", contravariant=True, bound=BaseClient)


@dataclass(frozen=True)
class Metric:
    instance: UUID
    comp: Completion
    weight_adjust: float
    weight: Weights
    label_width: int
    kind_width: int


class PReviewer(Protocol[_T]):
    async def register(self, assoc: BaseClient) -> None: ...

    async def begin(self, context: Context) -> _T: ...

    async def s_begin(self, token: _T, assoc: BaseClient, instance: UUID) -> None: ...

    def trans(self, token: _T, instance: UUID, completion: Completion) -> Metric: ...

    async def s_end(
        self, instance: UUID, interrupted: bool, elapsed: float, items: int
    ) -> None: ...


class Supervisor:
    def __init__(
        self,
        vars_dir: Path,
        display: Display,
        match: MatchOptions,
        comp: CompleteOptions,
        limits: Limits,
        reviewer: PReviewer,
    ) -> None:
        self.vars_dir = vars_dir
        self.match, self.display = match, display
        self.comp, self.limits = comp, limits
        self._reviewer = reviewer

        self.idling = Condition()
        self._workers: WeakSet[Worker] = WeakSet()

        self._lock = TracingLocker(name="Supervisor", force=True)
        self._work_task: Optional[Task] = None

    async def register(self, worker: Worker, assoc: BaseClient) -> None:
        with suppress_and_log():
            await self._reviewer.register(assoc)
            self._workers.add(worker)

    async def notify_idle(self) -> None:
        async with self.idling:
            self.idling.notify_all()

    async def interrupt(self) -> None:
        task = self._work_task
        self._work_task = None
        if task:
            await cancel(task)

    def collect(self, context: Context) -> Awaitable[Sequence[Metric]]:
        now = monotonic()
        timeout = (
            self.limits.completion_manual_timeout
            if context.manual
            else self.limits.completion_auto_timeout
        )

        async def cont(prev: Optional[Task]) -> Sequence[Metric]:
            with timeit("CANCEL -- ALL"):
                if prev:
                    await cancel(prev)

            with suppress_and_log(), timeit("COLLECTED -- ALL"):
                async with self._lock:
                    acc: MutableSequence[Metric] = []

                    token = await self._reviewer.begin(context)
                    tasks = tuple(
                        worker.supervised(context, token=token, now=now, acc=acc)
                        for worker in self._workers
                    )

                    _, pending = await wait(tasks, timeout=timeout)
                    if not acc:
                        for fut in as_completed(pending):
                            await fut
                            if acc:
                                break

                    await cancel(*pending)
                    return acc

        self._work_task = task = create_task(cont(self._work_task))
        return task


class Worker(Generic[_O_co, _T_co]):
    def __init__(self, supervisor: Supervisor, options: _O_co, misc: _T_co) -> None:
        self._work_task: Optional[Task] = None
        self._work_lock = TracingLocker(name=options.short_name, force=True)
        self._supervisor, self._options, self._misc = supervisor, options, misc
        create_task(self._supervisor.register(self, assoc=options))

    @abstractmethod
    async def interrupt(self) -> None: ...

    @abstractmethod
    def work(self, context: Context) -> AsyncIterator[Completion]: ...

    def supervised(
        self,
        context: Context,
        token: Any,
        now: float,
        acc: MutableSequence[Metric],
    ) -> Task:
        prev = self._work_task

        async def cont() -> None:
            instance, items = uuid4(), 0
            interrupted = False

            with timeit(f"CANCEL WORKER -- {self._options.short_name}"):
                if prev:
                    await cancel(prev)

            with suppress_and_log(), timeit(f"WORKER -- {self._options.short_name}"):
                await self._supervisor._reviewer.s_begin(
                    token, assoc=self._options, instance=instance
                )
                try:
                    async for items, completion in aenumerate(
                        self.work(context), start=1
                    ):
                        metric = self._supervisor._reviewer.trans(
                            token, instance=instance, completion=completion
                        )
                        acc.append(metric)
                except CancelledError:
                    interrupted = True
                    raise
                finally:
                    elapsed = monotonic() - now
                    await self._supervisor._reviewer.s_end(
                        instance,
                        interrupted=interrupted,
                        elapsed=elapsed,
                        items=items,
                    )

        self._work_task = task = create_task(cont())
        return task
