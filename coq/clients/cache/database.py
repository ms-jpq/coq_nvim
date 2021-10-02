from asyncio import CancelledError
from concurrent.futures import Executor
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterable, Iterator, Sequence

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db, like_esc
from ...shared.timeit import timeit
from .sql import sql


def _init() -> Connection:
    conn = Connection(":memory:", isolation_level=None)
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

    async def insert(self, words: Iterable[str]) -> None:
        def cont() -> None:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
                cursor.executemany(
                    sql("insert", "word"), ({"word": word} for word in words)
                )

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, clear: bool, opts: Options, word: str, sym: str, limitless: int
    ) -> Sequence[str]:
        def cont() -> Sequence[str]:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    if clear:
                        cursor.execute(sql("delete", "words"))
                        return ()
                    else:
                        limit = BIGGEST_INT if limitless else opts.max_results
                        cursor.execute(
                            sql("select", "words"),
                            {
                                "exact": opts.exact_matches,
                                "cut_off": opts.fuzzy_cutoff,
                                "look_ahead": opts.look_ahead,
                                "limit": limit,
                                "word": word,
                                "sym": sym,
                                "like_word": like_esc(word[: opts.exact_matches]),
                                "like_sym": like_esc(sym[: opts.exact_matches]),
                            },
                        )
                        rows = cursor.fetchall()
                        return tuple(row["word"] for row in rows)
            except OperationalError:
                return ()

        def step() -> Sequence[str]:
            self._interrupt()
            return self._ex.submit(cont)

        try:
            return await run_in_executor(step)
        except CancelledError:
            with timeit("INTERRUPT !! CACHE"):
                await run_in_executor(self._interrupt)
            raise
