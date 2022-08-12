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
from pathlib import Path
from time import monotonic
from typing import (
    AbstractSet,
    AsyncIterator,
    Awaitable,
    Generic,
    Iterator,
    MutableMapping,
    MutableSequence,
    Optional,
    Protocol,
    Sequence,
    Tuple,
    TypeVar,
)
from uuid import UUID, uuid4
from weakref import WeakKeyDictionary

from pynvim import Nvim
from pynvim_pp.lib import go
from pynvim_pp.logging import log, with_suppress
from std2.asyncio import cancel

from .settings import BaseClient, CompleteOptions, Limits, MatchOptions, Weights
from .timeit import timeit
from .types import Completion, Context

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


_SUPERVISOR_ID = uuid4()


class Supervisor:
    def __init__(
        self,
        pool: Executor,
        nvim: Nvim,
        vars_dir: Path,
        match: MatchOptions,
        comp: CompleteOptions,
        limits: Limits,
        reviewer: PReviewer,
    ) -> None:
        self.pool = pool
        self.vars_dir = vars_dir
        self.match, self.comp, self.limits = match, comp, limits
        self.nvim, self._reviewer = nvim, reviewer

        self.idling = Condition()
        self._workers: MutableMapping[Worker, BaseClient] = WeakKeyDictionary()

        self._lock = Lock()
        self._tasks: MutableMapping[UUID, Task] = {}

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

    def _consume_tasks(self) -> MutableMapping[UUID, Task]:
        tasks = {**self._tasks}
        self._tasks.clear()
        return tasks

    async def interrupt(self) -> None:
        await cancel(*self._consume_tasks().values())

    def collect(self, context: Context) -> Awaitable[Sequence[Metric]]:
        loop: AbstractEventLoop = self.nvim.loop
        t1, done = monotonic(), False
        timeout = (
            self.limits.completion_manual_timeout
            if context.manual
            else self.limits.completion_auto_timeout
        )

        acc: MutableSequence[Metric] = []

        async def supervise(
            worker: Worker, assoc: BaseClient, prev: Optional[Task]
        ) -> None:
            instance, items = uuid4(), 0

            with timeit(f"CANCEL WORKER -- {assoc.short_name}"):
                if prev:
                    await cancel(prev)

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

        async def cont(prev: MutableMapping[UUID, Task]) -> Sequence[Metric]:
            nonlocal done

            with timeit("CANCEL -- ALL"):
                if p := prev.pop(_SUPERVISOR_ID, None):
                    await cancel(p)

            with with_suppress(), timeit("COLLECTED -- ALL"):
                if self._lock.locked():
                    log.warn("%s", "SHOULD NOT BE LOCKED <><> supervisor")
                async with self._lock:
                    await self._reviewer.begin(context)
                    tasks = {
                        worker._uid: loop.create_task(
                            supervise(
                                worker,
                                assoc=assoc,
                                prev=prev.pop(worker._uid, None),
                            )
                        )
                        for worker, assoc in self._workers.items()
                    }
                    self._tasks.update(tasks)

                    try:
                        if not tasks:
                            return ()
                        else:
                            _, pending = await wait(
                                tuple(tasks.values()), timeout=timeout
                            )
                            if not acc:
                                for fut in as_completed(pending):
                                    await fut
                                    if acc:
                                        break
                            return acc
                    finally:
                        done = True

        task = loop.create_task(cont(self._consume_tasks()))
        self._tasks[_SUPERVISOR_ID] = task
        return task


class Worker(Generic[_O_co, _T_co]):
    def __init__(self, supervisor: Supervisor, options: _O_co, misc: _T_co) -> None:
        self._uid = uuid4()
        self._work_lock = Lock()
        self._supervisor, self._options, self._misc = supervisor, options, misc
        self._supervisor.register(self, assoc=options)

    def _check_locked(self) -> bool:
        locked = self._work_lock.locked()
        if locked:
            log.warn("%s", f"LOCKED :: {self._options.short_name}")
        return locked


    @abstractmethod
    def work(self, context: Context) -> AsyncIterator[Optional[Completion]]:
        ...
