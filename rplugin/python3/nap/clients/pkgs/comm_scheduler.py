from asyncio import Future, Queue
from logging import Logger
from typing import Awaitable, Callable, Dict, Tuple


def schedule(
    chan: Queue, log: Logger
) -> Tuple[Callable[[], Awaitable[None]], Callable[[int, Future], None]]:
    futs: Dict[int, Future] = {}

    async def background_update() -> None:
        nonlocal futs
        while True:
            rid, resp = await chan.get()
            log.debug("%s", f"rid = {rid}")
            fut = futs.pop(rid, None)
            if fut and not fut.cancelled():
                fut.set_result(resp)
            futs = {k: v for k, v in futs.items() if k > rid}

    def register(key: int, fut: Future) -> None:
        futs[key] = fut

    return background_update, register
