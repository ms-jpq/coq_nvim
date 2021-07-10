from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterator, Mapping, Sequence, Tuple, cast

from std2.asyncio import run_in_executor
from std2.sqllite3 import with_transaction

from ...consts import TREESITTER_DB
from ...shared.database import init_db
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from .sql import sql


def _init() -> Connection:
    conn = Connection(TREESITTER_DB, isolation_level=None)
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
        self, opts: Options, word: str, limit: int
    ) -> Sequence[Tuple[str, str, str]]:
        def cont() -> Sequence[Tuple[str, str, str]]:
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
                        return tuple(
                            (row["word"], row["kind"], row["sort_by"])
                            for row in cursor.fetchall()
                        )
            except OperationalError:
                return ()

        self._interrupt()
        ret = await run_in_executor(self._ex.submit, cont)
        return cast(Sequence[Tuple[str, str, str]], ret)

