from concurrent.futures import Executor
from contextlib import closing
from dataclasses import asdict
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterator, Mapping, Sequence

from std2.sqllite3 import with_transaction

from ...consts import TAGS_DB
from ...shared.database import init_db
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from .parser import Tag
from .reconciliate import Tag, Tags
from .sql import sql


def _init() -> Connection:
    conn = Connection(TAGS_DB, isolation_level=None)
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

    def add(self, tags: Tags) -> None:
        def m1() -> Iterator[Mapping]:
            for filename, info in tags.items():
                yield {
                    "filename": filename,
                    "filetype": info["lang"],
                }

        def m2() -> Iterator[Mapping]:
            for info in tags.values():
                for tag in info["tags"]:
                    yield asdict(tag)

        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("select", "files"), ())
                    existing = {row["filename"] for row in cursor.fetchall()}
                    dead = existing - tags.keys()
                    cursor.executemany(
                        sql("delete", "file"), ({"filename": d} for d in dead)
                    )
                    cursor.executemany(sql("insert", "file"), m1())
                    cursor.executemany(sql("insert", "tag"), m2())

        self._ex.submit(cont)

    def select(
        self, opts: Options, filetype: str, filename: str, line_num: int, word: str
    ) -> Sequence[Tag]:
        def cont() -> Sequence[Tag]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("select", "tags"),
                        {
                            "exact": opts.exact_matches,
                            "cut_off": opts.fuzzy_cutoff,
                            "filetype": filetype,
                            "filename": filename,
                            "line_num": line_num,
                            "word": word,
                        },
                    )
                    return tuple(row for row in cursor.fetchall())
            except OperationalError:
                return ()

        self._interrupt()
        return self._ex.submit(cont)

