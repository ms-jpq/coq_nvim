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

    def _interrupt(self, *, lock: bool = False) -> None:
        if lock:
            with self._lock:
                self._conn.interrupt()
        else:
            self._conn.interrupt()

    @contextmanager
    def _interruption(self, *, lock: bool = False) -> Iterator[None]:
        self._interrupt(lock=lock)
        try:
            yield None
        except CancelledError:
            self._interrupt(lock=lock)
            raise
