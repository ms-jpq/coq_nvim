from asyncio import Future, Queue
from logging import Logger
from typing import Awaitable, Callable, Tuple


def schedule(
    chan: Queue, log: Logger
) -> Tuple[Callable[[], Awaitable[None]], Callable[[int, Future], None]]:
    cid = -1
    c_fut: Future = Future()

    async def background_update() -> None:
        while True:
            rid, resp = await chan.get()
            if rid >= cid and not c_fut.done():
                c_fut.set_result(resp)

    def register(uid: int, fut: Future) -> None:
        nonlocal cid, c_fut
        if uid > cid:
            cid = uid
            c_fut.cancel()
            c_fut = fut
        else:
            fut.cancel()

    return background_update, register
