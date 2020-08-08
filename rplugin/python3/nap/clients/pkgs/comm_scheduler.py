from asyncio import Future, Queue
from logging import Logger
from typing import Awaitable, Callable, Dict, Tuple


def schedule(
    chan: Queue, log: Logger
) -> Tuple[Callable[[], Awaitable[None]], Callable[[int, Future], None]]:
    cid = -1
    c_fut: Future = Future()

    async def background_update() -> None:
        while True:
            rid, resp = await chan.get()
            log.debug("%s", f"reveived: rid: {rid}")
            if not c_fut.done():
                c_fut.set_result(resp)

    def register(uid: int, fut: Future) -> None:
        nonlocal cid, c_fut
        if uid > cid:
            cid = uid
            c_fut.cancel()
            c_fut = fut
        log.debug("%s", f"registered: uid: {uid}")

    return background_update, register
