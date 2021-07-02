from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterable, Sequence

from std2.sqllite3 import with_transaction

from ...shared.database import init_db
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from .sql import sql


def _init() -> Connection:
    conn = Connection(":memory:", isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class Database:
    def __init__(self, pool: Executor) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    def add(self, words: Iterable[str]) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("delete", "words"))
                    cursor.executemany(
                        sql("insert", "word"), ({"word": word} for word in words)
                    )

        self._ex.submit(cont)

    def select(self, opts: Options, word: str) -> Sequence[str]:
        def cont() -> Sequence[str]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("select", "words"),
                        {
                            "exact": opts.exact_matches,
                            "cut_off": opts.fuzzy_cutoff,
                            "word": word,
                        },
                    )
                    return tuple(row["word"] for row in cursor.fetchall())
            except OperationalError:
                return ()

        self._interrupt()
        return self._ex.submit(cont)

