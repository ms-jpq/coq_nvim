from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection
from typing import Mapping, Optional, cast

from std2.asyncio import run_in_executor
from std2.sqllite3 import with_transaction

from ....consts import INSERT_DB
from ....shared.database import init_db
from ....shared.executor import SingleThreadExecutor
from .sql import sql


def _init() -> Connection:
    conn = Connection(INSERT_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class IDB:
    def __init__(self, pool: Executor) -> None:
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def new_source(self, source: str) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("insert", "source"), {"name": source})

        self._ex.submit(cont)

    async def new_batch(self, source: str, batch_id: bytes) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("insert", "batch"),
                        {"rowid": batch_id, "source_id": source},
                    )

        await run_in_executor(self._ex.submit, cont)

    async def update_batch(
        self, batch_id: bytes, duration: Optional[float], items: Optional[int]
    ) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("update", "batch"),
                        {"batch_id": batch_id, "duration": duration, "items": items},
                    )

        await run_in_executor(self._ex.submit, cont)

    async def insertion_order(self, n_rows: int) -> Mapping[str, int]:
        def cont() -> Mapping[str, int]:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("select", "inserted"), {"limit": n_rows})
                    order = {
                        row["sort_by"]: row["insert_order"] for row in cursor.fetchall()
                    }
                    return order

        ret = await run_in_executor(self._ex.submit, cont)
        return cast(Mapping[str, int], ret)

    def inserted(self, batch_id: bytes, sort_by: str) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("insert", "inserted"),
                        {"batch_id": batch_id, "sort_by": sort_by},
                    )

        self._ex.submit(cont)

