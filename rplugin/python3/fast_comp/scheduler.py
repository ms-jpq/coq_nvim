from asyncio import FIRST_COMPLETED, Queue, Task, create_task, gather, sleep, wait
from math import inf
from typing import Any, AsyncIterator, Awaitable, Callable, TypeVar

T = TypeVar("T")


class Signal:
    def __eq__(self, o: Any) -> bool:
        return type(o) == Signal


sig = Signal()


async def schedule(chan: Queue, gen: Callable[[], Awaitable[T]]) -> AsyncIterator[T]:
    prev: Task = create_task(sleep(inf))

    def pp() -> Task:
        return prev

    async def wheel() -> AsyncIterator[T]:
        nonlocal prev
        done, pending = await wait((chan.get(), pp()), return_when=FIRST_COMPLETED)
        for d in await gather(*done):
            if d == sig:
                prev = create_task(gen())
            else:
                yield d
        for p in pending:
            p.cancel()

    while True:
        async for w in wheel():
            yield w
