from asyncio import create_subprocess_exec
from asyncio.subprocess import PIPE
from dataclasses import dataclass
from typing import AsyncIterator, Iterator, Optional, Sequence, TypeVar, cast

T = TypeVar("T")


def subsequences(seq: Sequence[T], reverse: bool = False) -> Iterator[Sequence[T]]:
    if not reverse:
        for i in range(1, len(seq)):
            yield seq[:i]
    if reverse:
        for i in range(len(seq) - 1, 0, -1):
            yield seq[i:]
    yield seq


async def anext(aiter: AsyncIterator[T], default: Optional[T] = None) -> Optional[T]:
    try:
        return await aiter.__anext__()
    except StopAsyncIteration:
        return default


@dataclass(frozen=True)
class ProcReturn:
    code: int
    out: str
    err: str


async def call(prog: str, *args: str) -> ProcReturn:
    proc = await create_subprocess_exec(prog, *args, stdout=PIPE, stderr=PIPE)
    stdout, stderr = await proc.communicate()
    code = cast(int, proc.returncode)
    return ProcReturn(code=code, out=stdout.decode(), err=stderr.decode())
