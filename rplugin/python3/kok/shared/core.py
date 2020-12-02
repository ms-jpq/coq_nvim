from asyncio import Task, create_task, sleep
from typing import Awaitable, Callable

from .logging import log


def run_forever(
    thing: Callable[[], Awaitable[None]],
    retries: int = 3,
    timeout: float = 1.0,
) -> Task:
    async def loop() -> None:
        for _ in range(retries):
            try:
                await thing()
            except Exception as e:
                log.exception("%s", e)
                await sleep(timeout)

    return create_task(loop())
