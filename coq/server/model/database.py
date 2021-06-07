from contextlib import closing
from sqlite3 import Connection
from sqlite3.dbapi2 import Cursor
from typing import AbstractSet, Iterable, Iterator, Mapping, Sequence, TypedDict

from std2.sqllite3 import with_transaction

from ...shared.parse import coalesce, lower, normalize
from .executor import Executor
from .sql import sql


class SqlMetrics(TypedDict):
    insertion_order: int
    ft_count: int
    line_diff: int


def _ensure_file(cursor: Cursor, file: str, filetype: str) -> None:
    cursor.execute(sql("insert", "filetype"), {"filetype": filetype})
    cursor.execute(
        sql("insert", "file"),
        {"filename": file, "filetype": filetype},
    )


def _init(location: str) -> Connection:
    conn = Connection(location)
    conn.create_function("X_LOWER", narg=1, func=lower, deterministic=True)
    conn.create_function("X_NORM", narg=1, func=normalize, deterministic=True)
    conn.executescript(sql("init", "pragma"))
    conn.executescript(sql("init", "tables"))
    return conn


class Database:
    def __init__(self, location: str) -> None:
        self._pool = Executor()
        self._conn: Connection = self._pool.submit(_init, location)

    def vaccum(self) -> None:
        def cont() -> None:
            self._conn.executescript(sql("vaccum", "periodical"))

        self._pool.submit(cont)

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
            words = tuple(
                tuple(coalesce(line, unifying_chars=unifying_chars)) for line in lines
            )

            def m1() -> Iterator[Mapping]:
                for line in words:
                    for word in line:
                        yield {"word": word, "lword": word.casefold()}

            def m2() -> Iterator[Mapping]:
                for line_num, line in enumerate(words, start=lo):
                    for word in line:
                        yield {
                            "word": word,
                            "filename": file,
                            "line_num": line_num,
                        }

            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_file(cursor, file=file, filetype=filetype)
                    cursor.execute(
                        sql("delete", "word_locations"),
                        {"lo": lo, "hi": hi},
                    )
                    cursor.executemany(sql("insert", "word"), m1())
                    cursor.executemany(sql("insert", "word_location"), m2())

        self._pool.submit(cont)

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

        self._pool.submit(cont)

    def suggestions(self, word: str, prefix_len: int) -> Sequence[str]:
        def cont() -> Sequence[str]:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("query", "words_by_prefix"),
                        {
                            "word": word,
                            "prefix_len": prefix_len,
                        },
                    )
                    return cursor.fetchall()

        return self._pool.submit(cont)

    def metric(
        self,
        words: Iterable[str],
        filetype: str,
        filename: str,
        line_num: int,
    ) -> Sequence[SqlMetrics]:
        def m1() -> Iterator[Mapping]:
            for word in words:
                yield {
                    "word": word,
                    "filetype": filetype,
                    "filename": filename,
                    "line_num": line_num,
                }

        def cont() -> Sequence[SqlMetrics]:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("query", "word_metrics"), m1())
                    return cursor.fetchall()

        return self._pool.submit(cont)
