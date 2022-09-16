from asyncio import Lock
from asyncio.exceptions import CancelledError
from contextlib import asynccontextmanager
from functools import cached_property
from sqlite3 import Connection
from typing import AsyncIterator, cast


class Interruptible:
    _conn: Connection = cast(Connection, None)

    @cached_property
    def _lock(self) -> Lock:
        return Lock()

    async def _interrupt(self) -> None:
        async with self._lock:
            self._conn.interrupt()

    @asynccontextmanager
    async def _interruption(self) -> AsyncIterator[None]:
        await self._interrupt()
        try:
            yield None
        except CancelledError:
            await self._interrupt()
            raise
