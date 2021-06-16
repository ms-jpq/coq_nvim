from contextlib import closing
from locale import strcoll
from sqlite3 import Connection, Row
from sqlite3.dbapi2 import Cursor
from typing import AbstractSet, Iterable, Iterator, Mapping, Sequence, TypedDict

from std2.sqllite3 import escape, with_transaction

from ...registry import pool
from ...shared.executor import Executor
from ...shared.parse import coalesce, lower, normalize
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


def _vaccum(conn: Connection) -> None:
    # conn.execute(sql("vaccum", "words"), {})
    pass


class Database:
    def __init__(self, location: str) -> None:
        self._ex = Executor(pool)
        self._conn: Connection = self._ex.submit(_init, location)

    def vaccum(self) -> None:
        self._ex.submit(_vaccum, self._conn)

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

    def insert(
        self,
        file: str,
        filetype: str,
        prefix: str,
        suffix: str,
        content: str,
    ) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_file(cursor, file=file, filetype=filetype)
                    cursor.execute(
                        sql("insert", "insertion"),
                        {
                            "prefix": prefix,
                            "suffix": suffix,
                            "filename": file,
                            "content": content,
                        },
                    )

        self._ex.submit(cont)

    def suggestions(self, prefix_len: int, cwd: str, word: str) -> Sequence[str]:
        def cont() -> Sequence[str]:
            with closing(self._conn.cursor()) as cursor:
                cursor.execute(
                    sql("select", "words_by_prefix"),
                    {
                        "prefix_len": prefix_len,
                        "cwd": cwd,
                        "word": word,
                    },
                )
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
                        for word in words:
                            cursor.execute(
                                sql("select", "word_metrics"),
                                {
                                    "word": word,
                                    "filetype": filetype,
                                    "filename": filename,
                                    "line_num": line_num,
                                },
                            )
                            yield cursor.fetchone()

            return tuple(c2())

        return self._ex.submit(cont)

