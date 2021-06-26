from concurrent.futures import ThreadPoolExecutor
from contextlib import closing, suppress
from sqlite3 import Connection, OperationalError
from string import Template
from threading import Lock
from typing import Iterable, Iterator, Mapping, Sequence, TypedDict

from std2.sqllite3 import with_transaction

from ...consts import TAGS_DB
from ...shared.database import init_db
from ...shared.executor import Executor
from .sql import sql


class _File(TypedDict):
    filename: str
    mtime: float


def _init() -> Connection:
    conn = Connection(TAGS_DB, isolation_level=None)
    init_db(conn)
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

    def ls_files(self) -> Sequence[_File]:
        def cont() -> Sequence[_File]:
            with self._lock, closing(self._conn.cursor()) as cursor:
                cursor.execute(sql("select", "file"), ())
                return cursor.fetchall()

        return self._ex.submit(cont)

    def vaccum(self, dead_files: Iterable[str]) -> None:
        def m1() -> Iterator[Mapping]:
            for filename in dead_files:
                yield {"filename": filename}

        def cont() -> None:
            with suppress(OperationalError):
                with closing(self._conn.cursor()) as cursor:
                    cursor.executemany(sql("delete", "file"), m1())

        self._ex.submit(cont)

    def add(self, panes: Mapping[str, Sequence[str]]) -> None:
        def cont() -> None:
            def it() -> Iterator[Mapping]:
                for pane_id, words in panes.items():
                    for word in words:
                        yield {
                            "pane_id": pane_id,
                            "word": word,
                        }

            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    template = Template(sql("delete", "words"))
                    cursor.execute(instruction, ())
                    cursor.executemany(sql("insert", "words"), it())

        self._ex.submit(cont)

    def select(
        self, word: str, filetype: str, filename: str, line_num: int
    ) -> Sequence[str]:
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

