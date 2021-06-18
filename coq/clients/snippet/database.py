from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from locale import strcoll
from sqlite3 import Connection, Row
from typing import Iterator, Mapping, Sequence, TypedDict

from std2.sqllite3 import escape, with_transaction

from ...consts import SNIPPET_DB
from ...shared.executor import Executor
from ...shared.parse import lower, normalize
from .sql import sql


class _Snip(TypedDict):
    prefix: str
    snippet: str
    grammar: str


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_"}, escape="!", param=like)
    return f"{escaped}%"


def _init() -> Connection:
    conn = Connection(SNIPPET_DB, isolation_level=None)
    conn.row_factory = Row
    conn.create_collation("X_COLL", strcoll)
    conn.create_function("X_LOWER", narg=1, func=lower, deterministic=True)
    conn.create_function("X_NORM", narg=1, func=normalize, deterministic=True)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class Database:
    def __init__(self, pool: ThreadPoolExecutor) -> None:
        self._ex = Executor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def select(self, word: str, filetype: str) -> Sequence[_Snip]:
        def cont() -> Sequence[_Snip]:
            with closing(self._conn.cursor()) as cursor:
                return ()

        return self._ex.submit(cont)

