from itertools import count
from typing import Awaitable, Callable, Tuple, Type, TypeVar

from .chan import Chan
from .types import Channel

T, U = TypeVar("T"), TypeVar("U")


def make_ch(
    t: Type[T], u: Type[U]
) -> Tuple[Channel[Tuple[int, T]], Channel[Tuple[int, U]]]:
    return Chan[T](), Chan[U]()


class OutdatedError(Exception):
    pass


def schedule(
    ask: Channel[Tuple[int, T]], reply: Channel[Tuple[int, U]]
) -> Callable[[T], Awaitable[U]]:
    it = count()
    uid = next(it)

    async def cont(qst: T) -> U:
        nonlocal uid
        uid = next(it)

        await ask.send((uid, qst))
        while True:
            rid, ans = await reply.recv()
            if rid < uid:
                pass
            elif rid > uid:
                await reply.send((rid, ans))
                raise OutdatedError()
            else:
                return ans

    return cont
