from asyncio import FIRST_COMPLETED, Queue, Task, create_task, gather, sleep, wait
from dataclasses import dataclass, field
from math import inf
from typing import (
    Any,
    AsyncIterator,
    Awaitable,
    Callable,
    Dict,
    Sequence,
    TypeVar,
    cast,
)

T = TypeVar("T")


@dataclass(frozen=True, eq=False)
class Signal:
    args: Sequence[Any] = ()
    kwargs: Dict[str, Any] = field(default_factory=dict)


async def schedule(chan: Queue, gen: Callable[..., Awaitable[T]]) -> AsyncIterator[T]:
    prev: Task = create_task(sleep(inf))

    while True:
        done, pending = await wait((chan.get(), prev), return_when=FIRST_COMPLETED)
        for d in await gather(*done):
            if type(d) is Signal:
                sig = cast(Signal, d)
                prev = create_task(gen(*sig.args, **sig.kwargs))
            else:
                prev = create_task(sleep(inf))
                yield d
        for p in pending:
            p.cancel()
