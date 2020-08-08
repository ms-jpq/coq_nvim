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
            log.debug("%d", rid)
            fut = futs.get(rid)
            if fut:
                fut.set_result(resp)

    def register(key: int, fut: Future) -> None:
        futs[key] = fut

    return background_update, register
