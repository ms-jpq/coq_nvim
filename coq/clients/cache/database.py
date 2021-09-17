from asyncio import CancelledError
from concurrent.futures import Executor
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import AbstractSet, Iterable, Iterator

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
from ...shared.timeit import timeit
from .sql import sql


def _init(unifying_chars: AbstractSet[str]) -> Connection:
    conn = Connection(":memory:", isolation_level=None)
    init_db(conn, unifying_chars=unifying_chars)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class Database:
    def __init__(self, pool: Executor, unifying_chars: AbstractSet[str]) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(lambda: _init(unifying_chars))

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
        self, clear: bool, options: Options, word: str, sym: str, limitless: int
    ) -> Iterator[str]:
        def cont() -> Iterator[str]:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    if clear:
                        cursor.execute(sql("delete", "words"))
                        return iter(())
                    else:
                        limit = BIGGEST_INT if limitless else options.max_results
                        cursor.execute(
                            sql("select", "words"),
                            {
                                "exact": options.exact_matches,
                                "cut_off": options.fuzzy_cutoff,
                                "look_ahead": options.look_ahead,
                                "limit": limit,
                                "word": word,
                                "sym": sym,
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
            with timeit("INTERRUPT !! CACHE"):
                await run_in_executor(self._interrupt)
            raise
