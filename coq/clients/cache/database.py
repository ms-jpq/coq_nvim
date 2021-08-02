from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterable, Iterator

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
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
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.executemany(
                        sql("insert", "word"), ({"word": word} for word in words)
                    )

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, clear: bool, options: Options, word: str, limitless: int
    ) -> Iterator[str]:
        def cont() -> Iterator[str]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        if clear:
                            cursor.execute(sql("delete", "words"))
                            return iter(())
                        else:
                            cursor.execute(
                                sql("select", "words"),
                                {
                                    "exact": options.exact_matches,
                                    "cut_off": options.fuzzy_cutoff,
                                    "look_ahead": options.look_ahead,
                                    "limit": BIGGEST_INT
                                    if limitless
                                    else options.max_results,
                                    "word": word,
                                },
                            )
                            rows = cursor.fetchall()
                            return (row["word"] for row in rows)
            except OperationalError:
                return iter(())

        def step() -> Iterator[str]:
            self._interrupt()
            return self._ex.submit(cont)

        return await run_in_executor(step)
