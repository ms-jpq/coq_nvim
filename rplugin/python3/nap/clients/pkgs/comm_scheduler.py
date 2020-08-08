from asyncio import Future, Queue
from logging import Logger
from typing import Awaitable, Callable, Dict, Tuple


def schedule(
    chan: Queue, log: Logger
) -> Tuple[Callable[[], Awaitable[None]], Callable[[int, Future], None]]:
    futs: Dict[int, Future] = {}

    async def background_update() -> None:
        while True:
            rid, resp = await chan.get()
            log.debug("%s", f"rid = {rid}")
            fut = futs.pop(rid, None)
            if fut and not fut.cancelled():
                fut.set_result(resp)
            keys = tuple(k for k in futs if k < rid)
            for key in keys:
                fut = futs.pop(key, None)
                if fut and not fut.cancelled():
                    fut.cancel()

    def register(key: int, fut: Future) -> None:
        futs[key] = fut

    return background_update, register
