from asyncio import FIRST_COMPLETED, Queue, wait
from asyncio.tasks import gather
from collections import deque
from typing import (
    Any,
    AsyncIterator,
    Awaitable,
    Callable,
    Deque,
    Generic,
    Sequence,
    Sized,
    TypeVar,
    cast,
)

from .types import Channel, ChannelClosed

T, U, V = TypeVar("T"), TypeVar("U"), TypeVar("V")


class BaseChan(Channel[T]):
    async def __aenter__(self) -> Channel[T]:
        return self

    async def __aexit__(self, *_: Any) -> None:
        await self.close()

    def __aiter__(self) -> AsyncIterator[T]:
        return self

    async def __anext__(self) -> T:
        try:
            return await self.recv()
        except ChannelClosed:
            raise StopAsyncIteration()


class Chan(BaseChan[T]):
    def __init__(self, size: int = 1) -> None:
        self._closed = False
        self._q: Queue = Queue(maxsize=size)

    def __bool__(self) -> bool:
        return not self._closed

    def __len__(self) -> int:
        return self._q.qsize()

    def full(self) -> bool:
        return (not self) or self._q.full()

    async def close(self) -> None:
        self._closed = True

    async def send(self, item: T) -> None:
        if self._closed:
            raise ChannelClosed()
        else:
            await self._q.put(item)

    async def recv(self) -> T:
        if self._closed:
            raise ChannelClosed()
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
            raise ChannelClosed()
        else:
            await gather(chan.send(item) for chan in self._chans)

    async def recv(self) -> T:
        self._prune()
        if not self:
            raise ChannelClosed()
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


class _ReducedChan(BaseChan[V], Generic[T], Generic[U]):
    def __init__(
        self, reducer: Callable[[U, T], Awaitable[V]], state: U, chan: Channel[T]
    ) -> None:
        self._reducer = reducer
        self._q = chan
        self._state = state

    def __bool__(self) -> bool:
        return bool(self._q)

    def __len__(self) -> int:
        return len(self._q)

    def full(self) -> bool:
        return self._q.full()

    async def close(self) -> None:
        await self._q.close()
        self._state = None

    async def send(self, item: T) -> None:
        await self._q.send(item)

    async def recv(self) -> T:
        curr = await self._q.recv()
        nxt = await self._reducer(self._state, curr)
        return nxt


def reduce(
    reducer: Callable[[U, T], Awaitable[V]], state: U, chan: Channel[T]
) -> Channel[V]:
    return _ReducedChan(reducer, state=state, chan=chan)