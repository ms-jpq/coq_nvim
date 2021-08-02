from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterable, Iterator, Mapping, Sequence

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import TMUX_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
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

    async def periodical(self, panes: Mapping[str, Sequence[str]]) -> None:
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
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("select", "panes"))
                    existing = {row["pane_id"] for row in cursor.fetchall()}
                    cursor.executemany(
                        sql("delete", "pane"), m1(existing - panes.keys())
                    )
                    cursor.executemany(sql("insert", "pane"), m1(panes.keys()))
                    cursor.executemany(sql("insert", "word"), m2())

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, opts: Options, active_pane: str, word: str, limitless: int
    ) -> Iterator[str]:
        def cont() -> Iterator[str]:
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
                                "pane_id": active_pane,
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
