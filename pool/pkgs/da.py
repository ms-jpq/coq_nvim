from typing import AsyncIterator, Optional, TypeVar

T = TypeVar("T")


async def anext(aiter: AsyncIterator[T], default: Optional[T] = None) -> Optional[T]:
    try:
        return await aiter.__anext__()
    except StopAsyncIteration:
        return default
