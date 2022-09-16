from asyncio.exceptions import CancelledError
from contextlib import contextmanager
from functools import cached_property
from sqlite3 import Connection
from threading import Lock
from typing import Iterator, cast


class Interruptible:
    _conn: Connection = cast(Connection, None)

    @cached_property
    def _lock(self) -> Lock:
        return Lock()

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    @contextmanager
    def _interruption(self) -> Iterator[None]:
        self._interrupt()
        try:
            yield None
        except CancelledError:
            self._interrupt()
            raise
