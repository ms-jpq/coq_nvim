from dataclasses import dataclass
from itertools import islice
from random import shuffle
from sqlite3 import Connection, OperationalError
from sqlite3.dbapi2 import Cursor
from typing import AbstractSet, Iterator, Mapping, Optional, Sequence, Tuple
from uuid import uuid4

from pynvim_pp.lib import recode
from std2.sqlite3 import with_transaction

from ...consts import BUFFER_DB, DEBUG
from ...shared.executor import SingleThreadExecutor
from ...shared.parse import coalesce
from ...shared.settings import MatchOptions
from ...shared.sql import BIGGEST_INT, init_db, like_esc
from ..types import Interruptible
from .sql import sql


@dataclass(frozen=True)
class BufferWord:
    text: str
    filetype: str
    filename: str
    line_num: int


def _ensure_buffer(cursor: Cursor, buf_id: int, filetype: str, filename: str) -> None:
    cursor.execute(sql("select", "buffer_by_id"), {"rowid": buf_id})
    row = {
        "rowid": buf_id,
        "filetype": filetype,
        "filename": filename,
    }
    if cursor.fetchone():
        cursor.execute(sql("update", "buffer"), row)
    else:
        cursor.execute(sql("insert", "buffer"), row)


def _init() -> Connection:
    conn = Connection(BUFFER_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class BDB(Interruptible):
    def __init__(
        self,
        tokenization_limit: int,
        unifying_chars: AbstractSet[str],
        include_syms: bool,
    ) -> None:

        self._ex = SingleThreadExecutor()
        self._tokenization_limit = tokenization_limit
        self._unifying_chars = unifying_chars
        self._include_syms = include_syms
        self._conn: Connection = self._ex.ssubmit(_init)

    async def vacuum(self, live_bufs: Mapping[int, int]) -> AbstractSet[int]:
        def cont() -> AbstractSet[int]:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    cursor.execute(sql("select", "buffers"), ())
                    existing = {row["rowid"] for row in cursor.fetchall()}
                    dead = existing - live_bufs.keys()
                    cursor.executemany(
                        sql("delete", "buffer"),
                        ({"buffer_id": buf_id} for buf_id in dead),
                    )
                    cursor.executemany(
                        sql("delete", "lines"),
                        (
                            {"buffer_id": buf_id, "lo": line_count, "hi": -1}
                            for buf_id, line_count in live_bufs.items()
                        ),
                    )
                    cursor.execute("PRAGMA optimize", ())
                    return dead
            except OperationalError:
                return set()

        return await self._ex.submit(cont)

    async def buf_update(self, buf_id: int, filetype: str, filename: str) -> None:
        def cont() -> None:
            with with_transaction(self._conn.cursor()) as cursor:
                _ensure_buffer(
                    cursor,
                    buf_id=buf_id,
                    filetype=filetype,
                    filename=filename,
                )

        async with self._lock:
            await self._ex.submit(cont)

    async def set_lines(
        self,
        buf_id: int,
        filetype: str,
        filename: str,
        lo: int,
        hi: int,
        lines: Sequence[str],
    ) -> None:
        def m0() -> Iterator[Tuple[int, str, bytes]]:
            for line_num, line in enumerate(lines, start=lo):
                line_id = uuid4().bytes
                yield line_num, recode(line), line_id

        line_info = [*m0()]
        shuffle(line_info)

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
                for word in coalesce(
                    self._unifying_chars,
                    include_syms=self._include_syms,
                    backwards=None,
                    chars=line,
                ):
                    yield {"line_id": line_id, "word": word, "line_num": line_num}

        def cont() -> None:
            with with_transaction(self._conn.cursor()) as cursor:
                _ensure_buffer(
                    cursor,
                    buf_id=buf_id,
                    filetype=filetype,
                    filename=filename,
                )
                cursor.execute(
                    sql("delete", "lines"),
                    {"buffer_id": buf_id, "lo": lo, "hi": hi},
                )
                shift = len(lines) - (hi - lo)
                cursor.execute(
                    sql("update", "lines_shift_1"),
                    {"buffer_id": buf_id, "lo": lo, "shift": shift},
                )
                cursor.execute(sql("update", "lines_shift_2"), {"buffer_id": buf_id})
                cursor.executemany(sql("insert", "line"), m1())
                cursor.executemany(
                    sql("insert", "word"), islice(m2(), self._tokenization_limit)
                )
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

        async with self._lock:
            await self._ex.submit(cont)

    async def words(
        self,
        opts: MatchOptions,
        filetype: Optional[str],
        word: str,
        sym: str,
        limitless: int,
    ) -> Iterator[BufferWord]:
        def cont() -> Iterator[BufferWord]:
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
                    return (
                        BufferWord(
                            text=row["word"],
                            filetype=row["filetype"],
                            filename=row["filename"],
                            line_num=row["line_num"] + 1,
                        )
                        for row in rows
                    )
            except OperationalError:
                return iter(())

        async with self._interruption():
            return await self._ex.submit(cont)
