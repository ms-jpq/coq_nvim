from asyncio import FIRST_COMPLETED, Queue, QueueEmpty, QueueFull, wait
from collections import deque
from random import choice
from typing import Any, AsyncIterator, Deque, Sequence, Sized, TypeVar, cast

from .types import Channel

T = TypeVar("T")


class BaseChan(Channel[T]):
    async def __aenter__(self) -> Channel[T]:
        return self

    async def __aexit__(self, *_: Any) -> None:
        await self.close()

    def __aiter__(self) -> AsyncIterator[T]:
        return self


class Chan(BaseChan[T]):
    def __init__(self, size: int = 1) -> None:
        self._closed = False
        self._q: Queue = Queue(maxsize=size)

    def __bool__(self) -> bool:
        return not self._closed

    def __len__(self) -> int:
        return self._q.qsize()

    async def __anext__(self) -> T:
        try:
            return await self.recv()
        except QueueEmpty:
            raise StopAsyncIteration()

    def full(self) -> bool:
        return (not self) or self._q.full()

    async def close(self) -> None:
        self._closed = True

    async def send(self, item: T) -> None:
        if self._closed:
            raise QueueFull()
        else:
            await self._q.put(item)

    async def recv(self) -> T:
        if self._closed:
            raise QueueEmpty()
        else:
            item = await self._q.get()
            return item


class _JoinedChan(BaseChan[T]):
    def __init__(self, chan: Channel[T], *chans: Channel[T]) -> None:
        self._q: Deque[T] = deque()
        self._chans: Sequence[Channel[T]] = tuple((chan, *chans))

    def __bool__(self) -> bool:
        return any(chan for chan in self._chans)

    def __len__(self) -> int:
        return sum(map(len, (cast(Sized, self._q), *self._chans)))

    async def __anext__(self) -> T:
        try:
            return await self.recv()
        except QueueEmpty:
            raise StopAsyncIteration()

    def full(self) -> bool:
        return all(chan.full() for chan in self._chans)

    async def close(self) -> None:
        for chan in self._chans:
            chan.close()
        self._chans = ()
        self._q.clear()

    def _prune(self) -> None:
        self._chans = tuple(chan for chan in self._chans if chan)

    async def send(self, item: T) -> None:
        self._prune()
        if not self:
            raise QueueFull()
        else:
            chan = next(
                (chan for chan in self._chans if not chan.full()), choice(self._chans)
            )
            await chan.send(item)

    async def recv(self) -> T:
        self._prune()
        if not self:
            raise QueueEmpty()
        else:
            if not self._q:
                done, pending = await wait(
                    (chan.recv() for chan in self._chans), return_when=FIRST_COMPLETED
                )
                for co in pending:
                    co.cancel()
                for co in done:
                    item = await co
                    self._q.append(item)

            return self._q.popleft()


def join(chan: Channel[T], *chans: Channel[T]) -> Channel[T]:
    return _JoinedChan(chan, *chans)
