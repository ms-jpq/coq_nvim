from contextlib import closing
from locale import strcoll
from sqlite3 import Connection, Row
from sqlite3.dbapi2 import Cursor
from typing import AbstractSet, Iterable, Iterator, Mapping, Sequence, TypedDict

from std2.sqllite3 import escape, with_transaction

from ...shared.parse import coalesce, lower, normalize
from .executor import Executor
from .sql import sql


class SqlMetrics(TypedDict):
    insertion_order: int
    ft_count: int
    line_diff: int


def _ensure_buffer(cursor: Cursor, buf: int, tick: int) -> None:
    cursor.execute(sql("insert", "buffer"), {"buffer": buf, "tick": tick})


def _ensure_file(cursor: Cursor, file: str, filetype: str) -> None:
    cursor.execute(sql("insert", "filetype"), {"filetype": filetype})
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
        self._pool = Executor()
        self._conn: Connection = self._pool.submit(_init, location)

    def vaccum(self) -> None:
        self._pool.submit(_vaccum, self._conn)

    def set_lines(
        self,
        buf: int,
        tick: int,
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

            def it() -> Iterator[Mapping]:
                for line_num, line in enumerate(words, start=lo):
                    for word in line:
                        yield {
                            "buffer": buf,
                            "word": word,
                            "filename": file,
                            "line_num": line_num,
                        }

            lst = tuple(it())
            del_param = {"filename": file, "lo": lo, "hi": hi}

            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_buffer(cursor, buf=buf, tick=tick)
                    _ensure_file(cursor, file=file, filetype=filetype)

                    cursor.execute(sql("delete", "words"), del_param)
                    cursor.execute(sql("delete", "word_locations"), del_param)

                    cursor.executemany(sql("insert", "word"), lst)
                    cursor.executemany(sql("insert", "word_location"), lst)

        self._pool.submit(cont)

    def set_tick(self, buf: int, tick: int) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_buffer(cursor, buf=buf, tick=tick)

        self._pool.submit(cont)

    def rm_buf(self, buf: int) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("delete", "buffer"), {"buffer": buf})

        self._pool.submit(cont)

    def ticks(self, buf: int) -> int:
        def cont() -> int:
            with closing(self._conn.cursor()) as cursor:
                cursor.execute(sql("select", "ticks"), {"buffer": buf})
                row = cursor.fetchone()

            return row["tick"]

        return self._pool.submit(cont)

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
                        sql("select", "words_by_prefix"),
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
                    cursor.execute(sql("select", "word_metrics"), m1())
                    return cursor.fetchall()

        return self._pool.submit(cont)
