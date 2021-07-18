from concurrent.futures import Executor
from contextlib import closing
from dataclasses import dataclass
from sqlite3 import Connection
from typing import Mapping, Sequence, cast

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import INSERT_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.sql import init_db
from .sql import sql


@dataclass(frozen=True)
class Statistics:
    source: str
    interrupted: int
    inserted: int

    avg_duration: float
    min_duration: int
    q50_duration: float
    q90_duration: float
    max_duration: float

    avg_items: float
    q50_items: int
    q90_items: int
    max_items: int


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

    async def new_batch(self, batch_id: bytes) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("insert", "batch"), {"rowid": batch_id})

        await run_in_executor(self._ex.submit, cont)

    async def new_instance(self, instance: bytes, source: str, batch_id: bytes) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("insert", "instance"),
                        {"rowid": instance, "source_id": source, "batch_id": batch_id},
                    )

        await run_in_executor(self._ex.submit, cont)

    async def instance_stat(
        self, instance: bytes, interrupted: bool, duration: float, items: int
    ) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("insert", "instance_stat"),
                        {
                            "instance_id": instance,
                            "interrupted": interrupted,
                            "duration": duration,
                            "items": items,
                        },
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

    def inserted(self, instance_id: bytes, sort_by: str) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("insert", "inserted"),
                        {"instance_id": instance_id, "sort_by": sort_by},
                    )

        self._ex.submit(cont)

    def stats(self) -> Sequence[Statistics]:
        def cont() -> Sequence[Statistics]:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("select", "stats"), ())
                    return tuple(Statistics(**row) for row in cursor.fetchall())

        return self._ex.submit(cont)

