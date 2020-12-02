from asyncio import FIRST_COMPLETED, Queue, Task, create_task, gather, sleep, wait
from dataclasses import dataclass, field
from itertools import count
from math import inf
from typing import (
    Any,
    AsyncIterator,
    Awaitable,
    Callable,
    Mapping,
    Sequence,
    Tuple,
    TypeVar,
    cast,
)

T = TypeVar("T")


@dataclass(frozen=True, eq=False)
class Signal:
    args: Sequence[Any] = ()
    kwargs: Mapping[str, Any] = field(default_factory=dict)


async def schedule(chan: Queue, gen: Callable[..., Awaitable[T]]) -> AsyncIterator[T]:
    it, curr = count(), -1
    prev: Task = create_task(sleep(inf))

    while True:
        done, pending = await wait((chan.get(), prev), return_when=FIRST_COMPLETED)
        for p in pending:
            p.cancel()
        for d in await gather(*done):
            if type(d) is Signal:
                sig = cast(Signal, d)
                curr = i = next(it)

                async def d_gen(*args: Any, **kwargs: Any) -> Tuple[int, T]:
                    ret = await gen(*args, **kwargs)
                    return i, ret

                prev = create_task(d_gen(*sig.args, **sig.kwargs))
            else:
                prev = create_task(sleep(inf))
                c, ret = d
                if c == curr:
                    yield ret
