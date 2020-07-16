from asyncio import FIRST_COMPLETED, Queue, sleep, wait
from typing import AsyncIterator, TypeVar

from .da import anext

T = TypeVar("T")


async def schedule(chan: Queue, gen: AsyncIterator[T]) -> AsyncIterator[T]:
    while True:
        await chan.get()
        t = await anext(gen)
        yield t
