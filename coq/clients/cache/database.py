from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Mapping, Sequence

from std2.asyncio import run_in_executor
from std2.sqllite3 import with_transaction

from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import init_db
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

    async def populate(self, additive: bool, pool: Mapping[bytes, str]) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    if not additive:
                        cursor.execute(sql("delete", "words"))
                    cursor.executemany(
                        sql("insert", "word"),
                        (
                            {"rowid": row_id, "word": word}
                            for row_id, word in pool.items()
                        ),
                    )

        await run_in_executor(self._ex.submit, cont)

    async def select(self, opts: Options, word: str, limit: int) -> Sequence[bytes]:
        def cont() -> Sequence[bytes]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(
                            sql("select", "words"),
                            {
                                "exact": opts.exact_matches,
                                "cut_off": opts.fuzzy_cutoff,
                                "limit": limit,
                                "word": word,
                            },
                        )
                        return tuple(row["rowid"] for row in cursor.fetchall())
            except OperationalError:
                return ()

        def step() -> Sequence[bytes]:
            self._interrupt()
            return self._ex.submit(cont)

        return await run_in_executor(step)

