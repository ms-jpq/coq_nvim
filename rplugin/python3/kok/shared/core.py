from asyncio import Task, create_task, sleep
from asyncio.tasks import gather
from typing import Awaitable, Callable

from .logging import log


def _run_forever(
    thing: Callable[[], Awaitable[None]],
    retries: int,
    timeout: float,
) -> Task:
    async def loop() -> None:
        for _ in range(retries):
            try:
                await thing()
            except Exception as e:
                log.exception("%s", e)
                await sleep(timeout)

    return create_task(loop())


async def run_forever(
    *things: Callable[[], Awaitable[None]],
    retries: int = 3,
    timeout: float = 1.0,
) -> Task:
    await gather(
        *(_run_forever(thing, retries=retries, timeout=timeout) for thing in things)
    )
