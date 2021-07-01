from contextlib import closing
from itertools import count, repeat
from sqlite3 import Connection, OperationalError
from sqlite3.dbapi2 import Cursor
from threading import Lock
from typing import AbstractSet, Iterator, Mapping, Sequence, Tuple, TypedDict

from std2.sqllite3 import with_transaction

from ....consts import BUFFERS_DB
from ....registry import pool
from ....shared.database import init_db
from ....shared.executor import SingleThreadExecutor
from ....shared.parse import coalesce
from ....shared.settings import Options
from ....shared.timeit import timeit
from .sql import sql


class SqlMetrics(TypedDict):
    wordcount: int
    insert_order: int


def _ensure_buffer(cursor: Cursor, buf_id: int, filetype: str) -> None:
    cursor.execute(
        sql("insert", "buffer"),
        {"rowid": buf_id, "filetype": filetype},
    )


def _init() -> Connection:
    conn = Connection(BUFFERS_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class BDB:
    def __init__(self) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)
        self._uid_gen = count()

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    def ft_update(self, buf_id: int, filetype: str) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_buffer(cursor, buf_id=buf_id, filetype=filetype)

        self._ex.submit(cont)

    def set_lines(
        self,
        buf_id: int,
        filetype: str,
        lo: int,
        hi: int,
        lines: Sequence[str],
        unifying_chars: AbstractSet[str],
    ) -> None:
        def m0() -> Iterator[Tuple[int, str, int]]:
            for (line_num, line), line_id in zip(
                enumerate(lines, start=lo), self._uid_gen
            ):
                yield line_num, line, line_id

        line_info = tuple(m0())

        def m1() -> Iterator[Mapping]:
            for line_num, line, line_id in line_info:
                yield {
                    "rowid": line_id,
                    "line": line,
                    "buffer_id": buf_id,
                    "line_num": line_num,
                }

        def m2() -> Iterator[Mapping]:
            for line_num, line, line_id in line_info:
                for word in coalesce(line, unifying_chars=unifying_chars):
                    yield {
                        "line_id": line_id,
                        "word": word,
                        "line_num": line_num,
                    }

        shift = len(lines) - (hi - lo)

        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_buffer(cursor, buf_id=buf_id, filetype=filetype)
                    del_params = {"buffer_id": buf_id, "lo": lo, "hi": hi}
                    cursor.execute(sql("delete", "lines"), del_params)
                    cursor.execute(
                        sql("update", "lines"),
                        {"buffer_id": buf_id, "lo": lo, "shift": shift},
                    )
                    cursor.executemany(sql("insert", "line"), m1())
                    cursor.executemany(sql("insert", "word"), m2())

        self._ex.submit(cont)

    def lines(self, buf_id: int, lo: int, hi: int) -> Tuple[int, Sequence[str]]:
        def cont() -> Tuple[int, Sequence[str]]:
            params = {"buffer_id": buf_id, "lo": lo, "hi": hi}
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("select", "line_count"), params)
                    count = cursor.fetchone()["line_count"]
                    cursor.execute(sql("select", "lines"), params)
                    lines = tuple(row["line"] for row in cursor.fetchall())
            return count, lines

        self._interrupt()
        return self._ex.submit(cont)

    def inserted(self, content: str) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("insert", "insertion"), {"content": content})

        self._ex.submit(cont)

    def suggestions(self, opts: Options, filetype: str, word: str) -> Sequence[str]:
        def cont() -> Sequence[str]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("select", "words_by_prefix"),
                        {
                            "exact": opts.exact_matches,
                            "cut_off": opts.fuzzy_cutoff,
                            "filetype": filetype,
                            "word": word,
                        },
                    )
                    return tuple(row["word"] for row in cursor.fetchall())
            except OperationalError:
                return ()

        return self._ex.submit(cont)

    def metric(self, filetype: str, words: Sequence[str]) -> Sequence[SqlMetrics]:
        def m1() -> Iterator[Mapping]:
            for word in words:
                yield {"filetype": filetype, "word": word}

        def cont() -> Sequence[SqlMetrics]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(sql("delete", "tmp_for_metrics"), ())
                        cursor.executemany(sql("insert", "tmp_for_metrics"), m1())
                        cursor.execute(sql("select", "metrics"))
                        return cursor.fetchall()
            except OperationalError:
                return tuple(
                    repeat(SqlMetrics(wordcount=0, insert_order=0), times=len(words))
                )

        return self._ex.submit(cont)

