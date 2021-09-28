from asyncio import CancelledError
from concurrent.futures import Executor
from sqlite3 import Connection, OperationalError
from sqlite3.dbapi2 import Cursor
from threading import Lock
from typing import AbstractSet, Iterator, Mapping, Optional, Sequence, Tuple
from uuid import uuid4

from pynvim_pp.lib import recode
from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import BUFFER_DB, DEBUG
from ...shared.executor import SingleThreadExecutor
from ...shared.parse import coalesce
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db, like_esc
from ...shared.timeit import timeit
from .sql import sql


def _ensure_buffer(cursor: Cursor, buf_id: int, filetype: str) -> None:
    cursor.execute(sql("select", "buffer_by_id"), {"rowid": buf_id})
    if cursor.fetchone():
        cursor.execute(
            sql("update", "buffer"),
            {"rowid": buf_id, "filetype": filetype},
        )
    else:
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

    async def vacuum(self, buf_ids: AbstractSet[int]) -> None:
        def cont() -> None:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    cursor.execute(sql("select", "buffers"), ())
                    existing = {row["rowid"] for row in cursor.fetchall()}
                    cursor.execute(
                        sql("delete", "buffers"),
                        ({"buf_id": buf_id} for buf_id in existing - buf_ids),
                    )
                    cursor.execute(sql("delete", "buffers"), ())
            except OperationalError:
                pass

        await run_in_executor(self._ex.submit, cont)

    async def del_bufs(self, buf_ids: AbstractSet[int]) -> None:
        def cont() -> None:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("delete", "buffers"),
                        ({"buf_id": buf_id} for buf_id in buf_ids),
                    )
                    cursor.execute(sql("delete", "buffers"), ())
            except OperationalError:
                pass

        await run_in_executor(self._ex.submit, cont)

    async def ft_update(self, buf_id: int, filetype: str) -> None:
        def cont() -> None:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
                _ensure_buffer(cursor, buf_id=buf_id, filetype=filetype)

        await run_in_executor(self._ex.submit, cont)

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
                yield line_num, recode(line), line_id

        line_info = tuple(m0())

        def m1() -> Iterator[Mapping]:
            for line_num, line, line_id in line_info:
                yield {
                    "rowid": line_id,
                    "buffer_id": buf_id,
                    "line_num": line_num,
                    "line": line if DEBUG else "",
                }

        def m2() -> Iterator[Mapping]:
            for line_num, line, line_id in line_info:
                for word in coalesce(line, unifying_chars=unifying_chars):
                    yield {"line_id": line_id, "word": word, "line_num": line_num}

        def cont() -> None:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
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

    def lines(self, buf_id: int, lo: int, hi: int) -> Tuple[int, Iterator[str]]:
        def cont() -> Tuple[int, Iterator[str]]:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
                cursor.execute(sql("select", "line_count"), {"buffer_id": buf_id})
                count = cursor.fetchone()["line_count"]
                cursor.execute(
                    sql("select", "lines"),
                    {"buffer_id": buf_id, "lo": lo, "hi": hi},
                )
                rows = cursor.fetchall()
                lines = (row["line"] for row in rows)
                return count, lines

        return self._ex.submit(cont)

    async def words(
        self,
        opts: Options,
        filetype: Optional[str],
        word: str,
        sym: str,
        limitless: int,
    ) -> Iterator[str]:
        def cont() -> Iterator[str]:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("select", "words"),
                        {
                            "cut_off": opts.fuzzy_cutoff,
                            "look_ahead": opts.look_ahead,
                            "limit": BIGGEST_INT if limitless else opts.max_results,
                            "filetype": filetype,
                            "word": word,
                            "sym": sym,
                            "like_word": like_esc(word[: opts.exact_matches]),
                            "like_sym": like_esc(sym[: opts.exact_matches]),
                        },
                    )
                    rows = cursor.fetchall()
                    return (row["word"] for row in rows)
            except OperationalError:
                return iter(())

        def step() -> Iterator[str]:
            self._interrupt()
            return self._ex.submit(cont)

        try:
            return await run_in_executor(step)
        except CancelledError:
            with timeit("INTERRUPT !! BUFFERS"):
                await run_in_executor(self._interrupt)
            raise
