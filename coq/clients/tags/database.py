from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterator, Mapping, Sequence, Tuple, cast

from std2.asyncio import run_in_executor
from std2.sqllite3 import with_transaction

from ...consts import TAGS_DB
from ...shared.database import init_db
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from .parser import Tag
from .reconciliate import Tag, Tags
from .sql import sql

_NIL_TAG = Tag(
    language="",
    path="",
    line=0,
    kind="",
    name="",
    pattern="",
    typeref=None,
    scope=None,
    scopeKind=None,
    access=None,
)


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

    async def add(self, tags: Tags) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("select", "files"), ())
                    files = {
                        row["filename"]: (row["filetype"], row["mtime"])
                        for row in cursor.fetchall()
                    }

                    def ded() -> Iterator[str]:
                        for f, (ft, mtime) in files.items():
                            info = tags.get(f)
                            if info:
                                if info["lang"] != ft or info["mtime"] != mtime:
                                    yield f
                            else:
                                yield f

                    dead = {*ded()}
                    live = files.keys() - dead

                    def m0() -> Iterator[Mapping]:
                        for f in dead:
                            yield {"filename": f}

                    def m1() -> Iterator[Mapping]:
                        for filename, info in tags.items():
                            if filename not in live:
                                yield {
                                    "filename": filename,
                                    "filetype": info["lang"],
                                    "mtime": info["mtime"],
                                }

                    def m2() -> Iterator[Mapping]:
                        for filename, info in tags.items():
                            if filename not in live:
                                for tag in info["tags"]:
                                    yield {**_NIL_TAG, **tag}

                    cursor.executemany(sql("delete", "file"), m0())
                    cursor.executemany(sql("insert", "file"), m1())
                    cursor.executemany(sql("insert", "tag"), m2())

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, opts: Options, filename: str, line_num: int, word: str, limit: int
    ) -> Sequence[Tuple[Tag, str]]:
        def cont() -> Sequence[Tuple[Tag, str]]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(
                            sql("select", "files_filetype"), {"filename": filename}
                        )
                        row = cursor.fetchone()
                        filetype = row["filetype"] if row else None
                        cursor.execute(
                            sql("select", "tags"),
                            {
                                "exact": opts.exact_matches,
                                "cut_off": opts.fuzzy_cutoff,
                                "limit": limit,
                                "filetype": filetype,
                                "filename": filename,
                                "line_num": line_num,
                                "word": word,
                            },
                        )
                        return tuple(
                            (cast(Tag, {**row}), row["sort_by"])
                            for row in cursor.fetchall()
                        )
            except OperationalError:
                return ()

        self._interrupt()
        ret = await run_in_executor(self._ex.submit, cont)
        return cast(Sequence[Tuple[Tag, str]], ret)

