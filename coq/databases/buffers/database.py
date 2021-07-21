from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from sqlite3.dbapi2 import Cursor
from threading import Lock
from typing import AbstractSet, Iterator, Mapping, Optional, Sequence, Tuple
from uuid import uuid4

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import BUFFER_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.parse import coalesce
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
from ...shared.timeit import timeit
from .sql import sql


def _ensure_buffer(cursor: Cursor, buf_id: int, filetype: str) -> None:
    cursor.execute(
        sql("insert", "buffer"),
        {"rowid": buf_id, "filetype": filetype},
    )


def _init() -> Connection:
    conn = Connection(BUFFER_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class BDB:
    def __init__(self, pool: Executor) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    async def ft_update(self, buf_id: int, filetype: str) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_buffer(cursor, buf_id=buf_id, filetype=filetype)

        await run_in_executor(self._ex.submit, cont)

    def vacuum(self, buf_ids: AbstractSet[int]) -> None:
        def cont() -> None:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(sql("select", "buffers"), ())
                        existing = {row["rowid"] for row in cursor.fetchall()}
                        cursor.execute(
                            sql("delete", "buffers"),
                            ({"buf_id": buf_id} for buf_id in existing - buf_ids),
                        )
                        cursor.execute(sql("delete", "buffers"), ())
            except OperationalError:
                pass

        self._ex.submit(cont)

    async def set_lines(
        self,
        buf_id: int,
        filetype: str,
        lo: int,
        hi: int,
        lines: Sequence[str],
        unifying_chars: AbstractSet[str],
    ) -> None:
        def m0() -> Iterator[Tuple[int, str, bytes]]:
            for line_num, line in enumerate(lines, start=lo):
                line_id = uuid4().bytes
                yield line_num, line, line_id

        line_info = tuple(m0())

        def m1() -> Iterator[Mapping]:
            for line_num, _, line_id in line_info:
                yield {"rowid": line_id, "buffer_id": buf_id, "line_num": line_num}

        def m2() -> Iterator[Mapping]:
            for line_num, line, line_id in line_info:
                for word in coalesce(line, unifying_chars=unifying_chars):
                    yield {"line_id": line_id, "word": word, "line_num": line_num}

        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_buffer(cursor, buf_id=buf_id, filetype=filetype)
                    cursor.execute(
                        sql("delete", "lines"),
                        {"buffer_id": buf_id, "lo": lo, "hi": hi},
                    )
                    shift = len(lines) - (hi - lo)
                    cursor.execute(
                        sql("update", "lines"),
                        {"buffer_id": buf_id, "lo": lo, "shift": shift},
                    )
                    cursor.executemany(sql("insert", "line"), m1())
                    cursor.executemany(sql("insert", "word"), m2())
                    cursor.execute(sql("select", "line_count"), {"buffer_id": buf_id})
                    count = cursor.fetchone()["line_count"]
                    if not count:
                        cursor.execute(
                            sql("insert", "line"),
                            {
                                "rowid": uuid4().bytes,
                                "line": "",
                                "buffer_id": buf_id,
                                "line_num": 0,
                            },
                        )

        await run_in_executor(self._ex.submit, cont)

    async def words(
        self, opts: Options, filetype: Optional[str], word: str, limitless: int
    ) -> Sequence[str]:
        def cont() -> Sequence[str]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(
                            sql("select", "words"),
                            {
                                "exact": opts.exact_matches,
                                "cut_off": opts.fuzzy_cutoff,
                                "look_ahead": opts.look_ahead,
                                "limit": BIGGEST_INT if limitless else opts.max_results,
                                "filetype": filetype,
                                "word": word,
                            },
                        )
                        return tuple(row["word"] for row in cursor.fetchall())
            except OperationalError:
                return ()

        def step() -> Sequence[str]:
            self._interrupt()
            return self._ex.submit(cont)

        return await run_in_executor(step)

