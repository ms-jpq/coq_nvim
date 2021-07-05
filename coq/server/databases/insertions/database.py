from contextlib import closing
from itertools import repeat
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Sequence, TypedDict

from std2.sqllite3 import with_transaction

from ....consts import BUFFERS_DB
from ....registry import pool
from ....shared.database import init_db
from ....shared.executor import SingleThreadExecutor
from ....shared.timeit import timeit
from .sql import sql


class SqlMetrics(TypedDict):
    insert_order: int


def _init() -> Connection:
    conn = Connection(BUFFERS_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class IDB:
    def __init__(self) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    def new_source(self, source: str) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("insert", "source"), {"name": source})

        self._ex.submit(cont)

    def new_batch(
        self, source: str, batch_id: bytes, duration: float, items: int
    ) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("insert", "batch"),
                        {
                            "rowid": batch_id,
                            "source_id": source,
                            "duration": duration,
                            "items": items,
                        },
                    )

        self._ex.submit(cont)

    def inserted(self, batch_id: bytes, sort_by: str) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("insert", "inserted"),
                        {"batch_id": batch_id, "sort_by": sort_by},
                    )

        self._ex.submit(cont)

    def metric(self, words: Sequence[str]) -> Sequence[SqlMetrics]:
        def cont() -> Sequence[SqlMetrics]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(sql("delete", "candidates"), ())
                        cursor.executemany(
                            sql("insert", "candidate"),
                            ({"sort_by": sort_by} for sort_by in words),
                        )
                        cursor.execute(sql("select", "metrics"))
                        return cursor.fetchall()
            except OperationalError:
                return tuple(repeat(SqlMetrics(insert_order=0), times=len(words)))

        return self._ex.submit(cont)

