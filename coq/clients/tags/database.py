from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterable, Iterator, Mapping, Sequence, Tuple, TypedDict

from std2.sqllite3 import with_transaction

from ...consts import TAGS_DB
from ...shared.database import init_db
from ...shared.executor import Executor
from .sql import sql
from .types import Section


class _File(TypedDict):
    filename: str
    mtime: float


class _Tag(TypedDict):
    name: str
    text: str
    filename: str
    line_num: int


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
                cursor.execute(sql("select", "files"), ())
                return cursor.fetchall()

        return self._ex.submit(cont)

    def vaccum(self, dead_files: Iterable[str]) -> None:
        def m1() -> Iterator[Mapping]:
            for filename in dead_files:
                yield {"filename": filename}

        dead = tuple(m1())

        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                cursor.executemany(sql("delete", "file"), dead)

        self._ex.submit(cont)

    def add(
        self, files: Mapping[Path, Tuple[str, float]], sections: Iterable[Section]
    ) -> None:
        def m1() -> Iterator[Mapping]:
            for filename, (filetype, mtime) in files.items():
                yield {
                    "filename": str(filename),
                    "filetype": filetype,
                    "mtime": mtime,
                }

        def m2() -> Iterator[Mapping]:
            for section in sections:
                for tag in section.tags:
                    yield {
                        "filename": section.header.filename,
                        "name": tag.name or tag.text,
                        "text": tag.text,
                        "line_num": tag.row,
                    }

        def cont() -> None:

            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.executemany(sql("insert", "file"), m1())
                    cursor.executemany(sql("insert", "tag"), m2())

        self._ex.submit(cont)

    def select(
        self, word: str, filetype: str, filename: str, line_num: int
    ) -> Sequence[_Tag]:
        def cont() -> Sequence[_Tag]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("select", "tags"),
                        {
                            "filetype": filetype,
                            "filename": filename,
                            "word": word,
                            "line_num": line_num,
                        },
                    )
                    return cursor.fetchall()
            except OperationalError:
                return ()

        self._interrupt()
        return self._ex.submit(cont)

