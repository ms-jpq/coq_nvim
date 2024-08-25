from asyncio import create_task, wait
from typing import Any, Coroutine, Optional, TypeVar

from std2.asyncio import cancel

_T = TypeVar("_T")


async def with_timeout(timeout: float, co: Coroutine[Any, Any, _T]) -> Optional[_T]:
    done, not_done = await wait((create_task(co),), timeout=timeout)
    await cancel(*not_done)
    return (await done.pop()) if done else None
