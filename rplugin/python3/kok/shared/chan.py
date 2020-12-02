from abc import abstractmethod
from asyncio import FIRST_COMPLETED, Queue, QueueEmpty, QueueFull, wait
from collections import deque
from typing import (
    AsyncIterable,
    AsyncIterator,
    Deque,
    Protocol,
    Sized,
    TypeVar,
    runtime_checkable,
)

T = TypeVar("T")


@runtime_checkable
class Channel(Sized, AsyncIterable[T], Protocol[T]):
    @abstractmethod
    def __bool__(self) -> bool:
        ...

    @abstractmethod
    async def __anext__(self) -> T:
        ...

    @abstractmethod
    def close(self) -> None:
        ...

    @abstractmethod
    async def send(self, item: T) -> None:
        ...

    @abstractmethod
    async def recv(self) -> T:
        ...


class Chan(Channel[T]):
    def __init__(self, size: int = 1) -> None:
        self._closed = False
        self._q: Queue = Queue(maxsize=size)

    def __bool__(self) -> bool:
        return self._closed

    def __len__(self) -> int:
        return self._q.qsize()

    def __aiter__(self) -> AsyncIterator[T]:
        return self

    async def __anext__(self) -> T:
        try:
            return await self.recv()
        except QueueEmpty:
            raise StopAsyncIteration()

    def close(self) -> None:
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


class _MergedChan(Channel[T]):
    def __init__(self, *chans: Channel[T]) -> None:
        self._closed = False
        self._q: Deque[T] = deque()
        self._chans = chans

    def __bool__(self) -> bool:
        return self._closed

    def __len__(self) -> int:
        return sum(map(len, (self._q, *self._chans)))

    def __aiter__(self) -> AsyncIterator[T]:
        return self

    async def __anext__(self) -> T:
        try:
            return await self.recv()
        except QueueEmpty:
            raise StopAsyncIteration()

    def close(self) -> None:
        self._closed = True
        self._q.clear()
        for chan in self._chans:
            chan.close()
        self._chans = ()

    async def send(self, item: T) -> None:
        self._chans = tuple(chan for chan in self._chans if chan)
        if not self._chans or self._closed:
            raise QueueFull()
        else:
            raise NotImplementedError

    async def recv(self) -> T:
        self._chans = tuple(chan for chan in self._chans if chan)
        if not self._chans or self._closed:
            raise QueueEmpty()
        else:
            done, pending = await wait(
                (chan.recv() for chan in self._chans), return_when=FIRST_COMPLETED
            )
            for co in pending:
                co.cancel()

            for co in done:
                item = await co
                self._q.append(item)
            return self._q.popleft()


async def merge(*chans: Channel[T]) -> Channel[T]:
    return _MergedChan(*chans)
