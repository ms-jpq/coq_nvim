from asyncio import CancelledError
from concurrent.futures import Executor
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterable, Iterator, Mapping

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import TMUX_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import MatchOptions
from ...shared.sql import BIGGEST_INT, init_db, like_esc
from ...shared.timeit import timeit
from .sql import sql


def _init() -> Connection:
    conn = Connection(TMUX_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class TMDB:
    def __init__(self, pool: Executor) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    async def periodical(self, panes: Mapping[str, Iterable[str]]) -> None:
        def m1(panes: Iterable[str]) -> Iterator[Mapping]:
            for pane_id in panes:
                yield {"pane_id": pane_id}

        def m2() -> Iterator[Mapping]:
            for pane_id, words in panes.items():
                for word in words:
                    yield {
                        "pane_id": pane_id,
                        "word": word,
                    }

        def cont() -> None:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
                cursor.execute(sql("select", "panes"))
                existing = {row["pane_id"] for row in cursor.fetchall()}
                cursor.executemany(sql("delete", "pane"), m1(existing - panes.keys()))
                cursor.executemany(sql("insert", "pane"), m1(panes.keys()))
                cursor.executemany(sql("insert", "word"), m2())
                cursor.execute("PRAGMA optimize", ())

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, opts: MatchOptions, active_pane: str, word: str, sym: str, limitless: int
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
                            "pane_id": active_pane,
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
            with timeit("INTERRUPT !! TMUX"):
                await run_in_executor(self._interrupt)
            raise
