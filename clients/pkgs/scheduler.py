from asyncio import FIRST_COMPLETED, Event, gather, sleep, wait
from time import time
from typing import AsyncIterator


async def schedule(
    chan: Event, min_time: float, max_time: float
) -> AsyncIterator[float]:
    async def wheel() -> float:
        t1 = time()
        done, pending = await wait(
            (chan.wait(), sleep(max_time)), return_when=FIRST_COMPLETED
        )
        chan.clear()
        for p in pending:
            p.cancel()
        await gather(*done)
        t2 = time()
        elapsed = t2 - t1
        await sleep(min_time - elapsed)
        return time() - t1

    while True:
        t = await wheel()
        yield t
