from sqlite3 import Connection
from typing import cast

from ..shared.types import Interruptible


class DB(Interruptible):
    _conn: Connection = cast(Connection, None)

    def interrupt(self) -> None:
        self._conn.interrupt()
