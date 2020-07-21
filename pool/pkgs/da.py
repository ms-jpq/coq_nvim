from typing import AsyncIterator, Iterator, Optional, Sequence, TypeVar

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


def contains_syms(text: str) -> bool:
    it = (c.isalnum() for c in text)
    return any(it)
