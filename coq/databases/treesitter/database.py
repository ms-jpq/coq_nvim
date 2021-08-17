from asyncio import CancelledError
from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterator, Mapping, Tuple

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import TREESITTER_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
from ...shared.timeit import timeit
from .sql import sql

_Word = str
_Kind = str
_Double = Tuple[_Word, _Kind]


def _init() -> Connection:
    conn = Connection(TREESITTER_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class TDB:
    def __init__(self, pool: Executor) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    async def new_nodes(self, nodes: Mapping[str, str]) -> None:
        def m1() -> Iterator[Mapping]:
            for text, kind in nodes.items():
                yield {"word": text, "kind": kind}

        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("delete", "words"))
                    cursor.executemany(sql("insert", "word"), m1())

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, opts: Options, word: str, limitless: int
    ) -> Iterator[_Double]:
        def cont() -> Iterator[_Double]:
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
                                "word": word,
                            },
                        )
                        rows = cursor.fetchall()
                        return ((row["word"], row["kind"]) for row in rows)
            except OperationalError:
                return iter(())

        def step() -> Iterator[_Double]:
            self._interrupt()
            return self._ex.submit(cont)

        try:
            return await run_in_executor(step)
        except CancelledError:
            with timeit("INTERRUPT !! TREESITTER"):
                await run_in_executor(self._interrupt)
            raise
