from typing import AsyncIterator, Awaitable, Optional, TypeVar

T = TypeVar("T")


async def anext(aiter: AsyncIterator[T], default: Optional[T] = None) -> Awaitable[T]:
    try:
        return await aiter.__anext__()
    except StopAsyncIteration:
        return default
