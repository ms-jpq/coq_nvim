from concurrent.futures import Executor
from contextlib import closing
from hashlib import md5
from os.path import normcase
from pathlib import PurePath
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import AbstractSet, Iterator, Mapping, cast

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import CLIENTS_DIR
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
from ...tags.types import Tag, Tags
from .sql import sql

_TAGS_DIR = CLIENTS_DIR / "tags"
_SCHEMA = "v0"

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


def _init(cwd: PurePath) -> Connection:
    ncwd = normcase(cwd)
    name = f"{md5(ncwd.encode()).hexdigest()}-{_SCHEMA}"
    db = (_TAGS_DIR / name).with_suffix(".sqlite3")
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = Connection(str(db), isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class CTDB:
    def __init__(self, pool: Executor, cwd: PurePath) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init, cwd)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    async def swap(self, cwd: PurePath) -> None:
        def cont() -> None:
            with self._lock:
                self._conn.close()
                self._conn = _init(cwd)

        await run_in_executor(self._ex.submit, cont)

    async def paths(self) -> Mapping[str, float]:
        def cont() -> Mapping[str, float]:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("select", "files"), ())
                    files = {row["filename"]: row["mtime"] for row in cursor.fetchall()}
                    return files

        def step() -> Mapping[str, float]:
            return self._ex.submit(cont)

        return await run_in_executor(step)

    async def reconciliate(self, dead: AbstractSet[str], new: Tags) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):

                    def m1() -> Iterator[Mapping]:
                        for filename, (lang, mtime, _) in new.items():
                            yield {
                                "filename": filename,
                                "filetype": lang,
                                "mtime": mtime,
                            }

                    def m2() -> Iterator[Mapping]:
                        for _, _, tags in new.values():
                            for tag in tags:
                                yield {**_NIL_TAG, **tag}

                    cursor.executemany(
                        sql("delete", "file"),
                        ({"filename": f} for f in dead | new.keys()),
                    )
                    cursor.executemany(sql("insert", "file"), m1())
                    cursor.executemany(sql("insert", "tag"), m2())

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, opts: Options, filename: str, line_num: int, word: str, limitless: int
    ) -> Iterator[Tag]:
        def cont() -> Iterator[Tag]:
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
                                "look_ahead": opts.look_ahead,
                                "limit": BIGGEST_INT if limitless else opts.max_results,
                                "filetype": filetype,
                                "filename": filename,
                                "line_num": line_num,
                                "word": word,
                            },
                        )
                        rows = cursor.fetchall()
                        return (cast(Tag, {**row}) for row in rows)
            except OperationalError:
                return iter(())

        def step() -> Iterator[Tag]:
            self._interrupt()
            return self._ex.submit(cont)

        return await run_in_executor(step)
