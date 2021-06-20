from contextlib import closing
from locale import strcoll
from sqlite3 import Connection, Row
from sqlite3.dbapi2 import Cursor
from typing import AbstractSet, Iterable, Iterator, Mapping, Sequence, TypedDict

from std2.sqllite3 import escape, with_transaction

from ....consts import BUFFERS_DB
from ....registry import pool
from ....shared.executor import Executor
from ....shared.parse import coalesce, lower, normalize
from .sql import sql


class SqlMetrics(TypedDict):
    insertion_order: int
    ft_count: int
    line_diff: int


def _ensure_file(cursor: Cursor, file: str, filetype: str) -> None:
    cursor.execute(
        sql("insert", "file"),
        {"filename": file, "filetype": filetype},
    )


def _like_esc(like: str) -> str:
    escaped = escape(nono={"%", "_"}, escape="!", param=like)
    return f"{escaped}%"


def _init() -> Connection:
    conn = Connection(BUFFERS_DB, isolation_level=None)
    conn.row_factory = Row
    conn.create_collation("X_COLL", strcoll)
    conn.create_function("X_LOWER", narg=1, func=lower, deterministic=True)
    conn.create_function("X_NORM", narg=1, func=normalize, deterministic=True)
    conn.create_function("X_LIKE_ESC", narg=1, func=_like_esc, deterministic=True)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class BDB:
    def __init__(self) -> None:
        self._ex = Executor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def vaccum(self) -> None:
        pass

    def ft_update(self, file: str, filetype: str) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_file(cursor, file=file, filetype=filetype)
                    cursor.execute(
                        sql("update", "files"), {"filename": file, "filetype": filetype}
                    )

        self._ex.submit(cont)

    def set_lines(
        self,
        file: str,
        filetype: str,
        lo: int,
        hi: int,
        lines: Sequence[str],
        unifying_chars: AbstractSet[str],
    ) -> None:
        def cont() -> None:
            def it() -> Iterator[Mapping]:
                for line_num, line in enumerate(lines, start=lo):
                    for word in coalesce(line, unifying_chars=unifying_chars):
                        yield {
                            "word": word,
                            "filename": file,
                            "line_num": line_num,
                        }

            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_file(cursor, file=file, filetype=filetype)
                    cursor.execute(
                        sql("delete", "words"), {"filename": file, "lo": lo, "hi": hi}
                    )
                    cursor.executemany(sql("insert", "words"), it())

        self._ex.submit(cont)

    def inserted(
        self,
        content: str,
    ) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("insert", "insertion"), {"content": content})

        self._ex.submit(cont)

    def suggestions(self, word: str) -> Sequence[str]:
        def cont() -> Sequence[str]:
            with closing(self._conn.cursor()) as cursor:
                cursor.execute(sql("select", "words_by_prefix"), {"word": word})
                return tuple(row["word"] for row in cursor.fetchall())

        return self._ex.submit(cont)

    def metric(
        self,
        words: Iterable[str],
        filetype: str,
        filename: str,
        line_num: int,
    ) -> Sequence[SqlMetrics]:
        def cont() -> Sequence[SqlMetrics]:
            def c2() -> Iterator[SqlMetrics]:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(
                            sql("select", "num_lines"), {"filename": filename}
                        )
                        lines_tot = cursor.fetchone()["lines_tot"]

                        for word in words:
                            cursor.execute(
                                sql("select", "word_metrics"),
                                {
                                    "word": word,
                                    "filetype": filetype,
                                    "filename": filename,
                                    "line_num": line_num,
                                    "lines_tot": lines_tot,
                                },
                            )
                            yield cursor.fetchone()

            return tuple(c2())

        return self._ex.submit(cont)

