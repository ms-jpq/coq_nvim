from contextlib import closing
from dataclasses import dataclass
from sqlite3 import Connection, OperationalError
from typing import Iterator, Mapping

from ...consts import INSERT_DB
from ...shared.executor import AsyncExecutor
from ...shared.sql import init_db
from ..types import Interruptible
from .sql import sql


@dataclass(frozen=True)
class Statistics:
    source: str
    interrupted: int
    inserted: int

    avg_duration: float
    q10_duration: float
    q50_duration: float
    q95_duration: float
    q99_duration: float

    avg_items: float
    q50_items: int
    q99_items: int


def _init() -> Connection:
    conn = Connection(INSERT_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class IDB(Interruptible):
    def __init__(self) -> None:
        self._ex = AsyncExecutor()
        self._conn: Connection = self._ex.ssubmit(_init)

    async def new_source(self, source: str) -> None:
        def c1() -> None:
            with self._conn, closing(self._conn.cursor()) as cursor:
                cursor.execute(sql("insert", "source"), {"name": source})

        async with self._lock:
            self._ex.submit(c1)

    async def new_batch(self, batch_id: bytes) -> None:
        def cont() -> None:
            with self._conn, closing(self._conn.cursor()) as cursor:
                cursor.execute(sql("insert", "batch"), {"rowid": batch_id})

        async with self._lock:
            await self._ex.submit(cont)

    async def new_instance(self, instance: bytes, source: str, batch_id: bytes) -> None:
        def cont(_: None = None) -> None:
            with self._conn, closing(self._conn.cursor()) as cursor:
                cursor.execute(
                    sql("insert", "instance"),
                    {"rowid": instance, "source_id": source, "batch_id": batch_id},
                )

        async with self._lock:
            await self._ex.submit(cont)

    async def new_stat(
        self, instance: bytes, interrupted: bool, duration: float, items: int
    ) -> None:
        def cont() -> None:
            with self._conn, closing(self._conn.cursor()) as cursor:
                cursor.execute(
                    sql("insert", "instance_stat"),
                    {
                        "instance_id": instance,
                        "interrupted": interrupted,
                        "duration": duration,
                        "items": items,
                    },
                )

        async with self._lock:
            await self._ex.submit(cont)

    async def insertion_order(self, n_rows: int) -> Mapping[str, int]:
        def cont() -> Mapping[str, int]:
            try:
                with self._conn, closing(self._conn.cursor()) as cursor:
                    cursor.execute(sql("select", "inserted"), {"limit": n_rows})
                    order = {
                        row["sort_by"]: row["insert_order"] for row in cursor.fetchall()
                    }
                    return order
            except OperationalError:
                return {}

        async with self._interruption():
            return await self._ex.submit(cont)

    async def inserted(self, instance_id: bytes, sort_by: str) -> None:
        def cont() -> None:
            with self._conn, closing(self._conn.cursor()) as cursor:
                cursor.execute(
                    sql("insert", "inserted"),
                    {"instance_id": instance_id, "sort_by": sort_by},
                )

        async with self._lock:
            self._ex.submit(cont)

    async def stats(self) -> Iterator[Statistics]:
        def cont() -> Iterator[Statistics]:
            with self._conn, closing(self._conn.cursor()) as cursor:
                cursor.execute(sql("select", "summaries"), ())
                rows = cursor.fetchall()

            def c1() -> Iterator[Statistics]:
                for row in rows:
                    stat = Statistics(
                        source=row["source"],
                        interrupted=row["interrupted"],
                        inserted=row["inserted"],
                        avg_duration=row["avg_duration"],
                        avg_items=row["avg_items"],
                        q10_duration=row["q10_duration"],
                        q50_duration=row["q50_duration"],
                        q95_duration=row["q95_duration"],
                        q99_duration=row["q99_duration"],
                        q50_items=row["q50_items"],
                        q99_items=row["q99_items"],
                    )
                    yield stat

            return c1()

        async with self._lock:
            return await self._ex.submit(cont)
