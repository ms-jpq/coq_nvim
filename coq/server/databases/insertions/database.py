from contextlib import closing
from itertools import count, repeat
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterator, Mapping, Sequence, TypedDict

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
        self._uid_gen = count()

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    def inserted(self, content: str) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("insert", "insertion"), {"content": content})

        self._ex.submit(cont)

    def metric(self, words: Sequence[str]) -> Sequence[SqlMetrics]:
        def m1() -> Iterator[Mapping]:
            for word in words:
                yield {"word": word}

        def cont() -> Sequence[SqlMetrics]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(sql("delete", "tmp_for_metrics"), ())
                        cursor.executemany(sql("insert", "tmp_for_metrics"), m1())
                        cursor.execute(sql("select", "metrics"))
                        return cursor.fetchall()
                return tuple(
                    repeat(SqlMetrics(wordcount=0, insert_order=0), times=len(words))
                )
            except OperationalError:
                return tuple(
                    repeat(SqlMetrics(wordcount=0, insert_order=0), times=len(words))
                )

        return self._ex.submit(cont)

