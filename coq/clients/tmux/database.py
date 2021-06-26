from concurrent.futures import ThreadPoolExecutor
from contextlib import closing, suppress
from locale import strcoll
from sqlite3 import Connection, OperationalError, Row
from threading import Lock
from typing import Iterator, Mapping, Sequence

from std2.sqllite3 import escape, with_transaction

from ...consts import TMUX_DB
from ...shared.executor import Executor
from ...shared.parse import lower, normalize
from .sql import sql


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_"}, escape="!", param=like)
    return f"{escaped}%"


def _init() -> Connection:
    conn = Connection(TMUX_DB, isolation_level=None)
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
        self._lock = Lock()
        self._ex = Executor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    def periodical(self, panes: Mapping[str, Sequence[str]]) -> None:
        def m2() -> Iterator[Mapping]:
            for pane_id, words in panes.items():
                for word in words:
                    yield {
                        "pane_id": pane_id,
                        "word": word,
                    }

        def cont() -> None:
            with suppress(OperationalError):
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(sql("select", "panes"))
                        existing = {row["pane_id"] for row in cursor.fetchall()}
                        gone = ({"pane_id": pane} for pane in existing - panes.keys())
                        cursor.executemany(sql("delete", "pane"), gone)
                        cursor.executemany(sql("insert", "word"), m2())

        self._ex.submit(cont)

    def select(self, word: str, active_pane: str) -> Sequence[str]:
        def cont() -> Sequence[str]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("select", "words"),
                        {
                            "pane_id": active_pane,
                            "word": word,
                        },
                    )
                    return tuple(row["word"] for row in cursor.fetchall())
            except OperationalError:
                return ()

        self._interrupt()
        return self._ex.submit(cont)

