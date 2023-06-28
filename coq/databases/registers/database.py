from contextlib import suppress
from dataclasses import dataclass
from itertools import chain
from sqlite3 import Connection, Cursor, OperationalError
from typing import AbstractSet, Any, Iterator, Mapping, Sequence

from std2.sqlite3 import with_transaction

from ...consts import REGISTER_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.parse import coalesce, tokenize
from ...shared.settings import MatchOptions
from ...shared.sql import BIGGEST_INT, init_db, like_esc
from ..types import Interruptible
from .sql import sql


@dataclass(frozen=True)
class RegWord:
    text: str
    match: str
    regname: str


def _init() -> Connection:
    conn = Connection(REGISTER_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class RDB(Interruptible):
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

    async def periodical(
        self,
        wordreg: Mapping[str, str],
        linereg: Mapping[str, str],
    ) -> None:
        m1 = (*wordreg, *linereg)

        def m2() -> Iterator[Mapping]:
            for reg, text in wordreg.items():
                for word in tokenize(
                    self._tokenization_limit,
                    unifying_chars=self._unifying_chars,
                    include_syms=self._include_syms,
                    text=text,
                ):
                    yield {"register": reg, "word": word}

        def m3() -> Iterator[Mapping]:
            for reg, text in linereg.items():
                for row in text.splitlines():
                    if line := row.strip():
                        tokens = coalesce(
                            self._unifying_chars,
                            include_syms=True,
                            backwards=False,
                            chars=line,
                        )
                        if word := next(tokens, None):
                            yield {"register": reg, "word": word, "line": line}

        def cont() -> None:
            with suppress(OperationalError):
                with with_transaction(self._conn.cursor()) as cursor:
                    cursor.executemany(sql("delete", "register"), m1)
                    cursor.executemany(sql("insert", "register"), m1)
                    cursor.executemany(sql("insert", "word"), m2())
                    cursor.executemany(sql("insert", "line"), m3())
                    cursor.execute("PRAGMA optimize", ())

        await self._ex.submit(cont)

    async def select(
        self, lines: bool, opts: MatchOptions, word: str, sym: str, limitless: int
    ) -> Iterator[RegWord]:
        def fetch(cursor: Cursor, f: str) -> Sequence[Any]:
            cursor.execute(
                sql("select", f),
                {
                    "cut_off": opts.fuzzy_cutoff,
                    "look_ahead": opts.look_ahead,
                    "limit": BIGGEST_INT if limitless else opts.max_results,
                    "word": word,
                    "sym": sym,
                    "like_word": like_esc(word[: opts.exact_matches]),
                    "like_sym": like_esc(sym[: opts.exact_matches]),
                },
            )
            return cursor.fetchall()

        def cont() -> Iterator[RegWord]:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    rows = chain(
                        fetch(cursor, "lines") if lines else (), fetch(cursor, "words")
                    )
                    return (
                        RegWord(
                            regname=row["register"],
                            text=row["text"],
                            match=row["word"],
                        )
                        for row in rows
                    )
            except OperationalError:
                return iter(())

        async with self._interruption():
            return await self._ex.submit(cont)
