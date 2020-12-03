from asyncio import FIRST_COMPLETED, Queue, wait
from asyncio.tasks import gather
from collections import deque
from typing import (
    Any,
    AsyncIterator,
    Callable,
    Deque,
    Generic,
    Sequence,
    Sized,
    TypeVar,
    cast,
)

from .types import Channel, ChannelClosed

T, U = TypeVar("T"), TypeVar("U")


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
    def __init__(self) -> None:
        self._closed = False
        self._q: Queue = Queue(maxsize=1)

    def __bool__(self) -> bool:
        return not self._closed

    def __len__(self) -> int:
        return self._q.qsize()

    async def close(self) -> None:
        self._closed = True

    async def send(self, item: T) -> None:
        if not self:
            raise ChannelClosed()
        else:
            await self._q.put(item)

    async def recv(self) -> T:
        if not self:
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

    async def close(self) -> None:
        for chan in self._chans:
            chan.close()
        self._chans = ()
        self._q.clear()

    async def send(self, item: T) -> None:
        if not self:
            raise ChannelClosed()
        else:
            await gather(chan.send(item) for chan in self._chans if chan)

    async def recv(self) -> T:
        if not self:
            raise ChannelClosed()
        else:
            if not self._q:
                done, pending = await wait(
                    (chan.recv() for chan in self._chans if chan),
                    return_when=FIRST_COMPLETED,
                )
                for co in pending:
                    co.cancel()
                for item in await gather(*done):
                    self._q.append(item)

            return self._q.popleft()


def join(chan: Channel[T], *chans: Channel[T]) -> Channel[T]:
    return _JoinedChan(chan, *chans)


class _TransChan(BaseChan[T], Generic[U]):
    def __init__(
        self,
        trans: Callable[[AsyncIterator[U]], AsyncIterator[T]],
        chan: Channel[U],
    ) -> None:
        self._q = chan
        self._buf = Chan[T]()
        self._it = trans(chan)

    def __bool__(self) -> bool:
        return self._q and self._buf

    def __len__(self) -> int:
        return len(self._q) + len(self._buf)

    async def close(self) -> None:
        await gather(self._q.close(), self._buf.close())

    async def send(self, item: T) -> None:
        await self._buf.send(item)

    async def recv(self) -> T:
        async def cont() -> T:
            try:
                return await self._it.__anext__()
            except StopAsyncIteration:
                raise RuntimeError()

        if not self:
            raise ChannelClosed()
        elif len(self._q):
            return await cont()
        elif len(self._buf):
            return await self._buf.recv()
        else:
            return await cont()


def trans(
    trans: Callable[[AsyncIterator[T]], AsyncIterator[U]],
    chan: Channel[T],
) -> Channel[U]:
    return _TransChan(trans, chan=chan)
