from asyncio import CancelledError
from concurrent.futures import Executor
from contextlib import suppress
from dataclasses import dataclass
from itertools import islice
from sqlite3 import Connection, OperationalError
from typing import AbstractSet, Iterable, Iterator, Mapping, Optional

from std2.asyncio import to_thread
from std2.sqlite3 import with_transaction

from ...consts import TMUX_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import MatchOptions
from ...shared.sql import BIGGEST_INT, init_db, like_esc
from ...shared.timeit import timeit
from ...tmux.parse import Pane
from .sql import sql


@dataclass(frozen=True)
class TmuxWord:
    text: str
    session_name: str
    window_index: int
    window_name: str
    pane_index: int
    pane_title: str


def _init() -> Connection:
    conn = Connection(TMUX_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class TMDB:
    def __init__(self, pool: Executor, tokenization_limit: int) -> None:
        self._ex = SingleThreadExecutor(pool)
        self._current = Optional[Pane]
        self._tokenization_limit = tokenization_limit
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        self._conn.interrupt()

    async def periodical(
        self, current: Optional[Pane], panes: Mapping[Pane, Iterable[str]]
    ) -> None:
        self._current = current

        def m1(existing: AbstractSet[str]) -> Iterator[Mapping]:
            for uid in existing - {pane.uid for pane in panes}:
                yield {"pane_id": uid}

        def m2(panes: Iterable[Pane]) -> Iterator[Mapping]:
            for pane in panes:
                yield {
                    "pane_id": pane.uid,
                    "session_name": pane.session_name,
                    "window_index": pane.window_index,
                    "window_name": pane.window_name,
                    "pane_index": pane.pane_index,
                    "pane_title": pane.pane_title,
                }

        def m3() -> Iterator[Mapping]:
            for pane, words in panes.items():
                if not current or pane.uid != current.uid:
                    for word in islice(words, self._tokenization_limit):
                        yield {
                            "pane_id": pane.uid,
                            "word": word,
                        }

        def cont() -> None:
            with suppress(OperationalError):
                with with_transaction(self._conn.cursor()) as cursor:
                    cursor.execute(sql("select", "panes"))
                    existing = {row["pane_id"] for row in cursor.fetchall()}
                    cursor.executemany(sql("delete", "pane"), m1(existing))
                    cursor.executemany(sql("insert", "pane"), m2(panes))
                    cursor.executemany(sql("insert", "word"), m3())
                    cursor.execute("PRAGMA optimize", ())

        await self._ex.asubmit(cont)

    async def select(
        self, opts: MatchOptions, word: str, sym: str, limitless: int
    ) -> Iterator[TmuxWord]:
        def cont() -> Iterator[TmuxWord]:
            if active_pane := self._current:
                try:
                    with with_transaction(self._conn.cursor()) as cursor:
                        cursor.execute(
                            sql("select", "words"),
                            {
                                "cut_off": opts.fuzzy_cutoff,
                                "look_ahead": opts.look_ahead,
                                "limit": BIGGEST_INT if limitless else opts.max_results,
                                "pane_id": active_pane.uid,
                                "word": word,
                                "sym": sym,
                                "like_word": like_esc(word[: opts.exact_matches]),
                                "like_sym": like_esc(sym[: opts.exact_matches]),
                            },
                        )
                        rows = cursor.fetchall()
                        return (
                            TmuxWord(
                                text=row["word"],
                                session_name=row["session_name"],
                                window_index=row["window_index"],
                                window_name=row["window_name"],
                                pane_index=row["pane_index"],
                                pane_title=row["pane_title"],
                            )
                            for row in rows
                        )
                except OperationalError:
                    return iter(())
            else:
                return iter(())

        await to_thread(self._interrupt)
        try:
            return await self._ex.asubmit(cont)
        except CancelledError:
            with timeit("INTERRUPT !! TMUX"):
                await to_thread(self._interrupt)
            raise
