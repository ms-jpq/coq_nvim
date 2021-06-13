from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from locale import strcoll
from sqlite3 import Connection, Row
from sqlite3.dbapi2 import Cursor
from typing import Mapping, Sequence

from std2.sqllite3 import escape, with_transaction

from ...shared.executor import Executor
from ...shared.parse import coalesce, lower, normalize
from .sql import sql, sqlt


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_"}, escape="!", param=like)
    return f"{escaped}%"


def _init(location: str) -> Connection:
    conn = Connection(location, isolation_level=None)
    conn.row_factory = Row
    conn.create_collation("X_COLL", strcoll)
    conn.create_function("X_LOWER", narg=1, func=lower, deterministic=True)
    conn.create_function("X_NORM", narg=1, func=normalize, deterministic=True)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class Database:
    def __init__(self, pool: ThreadPoolExecutor, location: str) -> None:
        self._pool = Executor(pool)
        self._conn: Connection = self._pool.submit(_init, location)

    def periodical(self, panes: Mapping[str, Sequence[str]]) -> None:
        pass

    def select(self, word: str, active_pane: str) -> Sequence[str]:
        return ()

