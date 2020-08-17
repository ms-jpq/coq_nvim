from __future__ import annotations

from asyncio import Lock
from contextlib import AbstractAsyncContextManager
from sqlite3 import Connection, Cursor, Row, connect
from typing import (
    Any,
    AsyncIterator,
    Iterable,
    Iterator,
    Optional,
    Sequence,
    Set,
    Union,
)

from .executor import Executor

SQL_TYPES = Union[int, float, str, bytes, None]


class ACursor(AbstractAsyncContextManager):
    def __init__(self, chan: Executor, cursor: Cursor) -> None:
        self._chan = chan
        self._cursor = cursor

    async def __aexit__(self, *_: Any) -> None:
        await self._chan.run(self._cursor.close)

    @property
    def lastrowid(self) -> int:
        return self._cursor.lastrowid

    async def fetch_one(self) -> Row:
        return await self._chan.run(self._cursor.fetchone)

    async def fetch_all(self) -> Sequence[Row]:
        return await self._chan.run(self._cursor.fetchall)

    async def execute(self, sql: str, params: Iterable[SQL_TYPES] = ()) -> None:
        def cont() -> None:
            self._cursor.execute(sql, params)

        await self._chan.run(cont)

    async def execute_many(
        self, sql: str, params: Iterable[Iterable[SQL_TYPES]] = ()
    ) -> None:
        def cont() -> None:
            self._cursor.executemany(sql, params)

        await self._chan.run(cont)


class AConnection(AbstractAsyncContextManager):
    def __init__(self, database: str = ":memory:") -> None:
        self.chan = Executor()
        self.lock = Lock()

        def cont() -> Connection:
            conn = connect(database)
            conn.row_factory = Row
            return conn

        self._conn = self.chan.run_sync(cont, database)

    async def __aexit__(self, *_: Any) -> None:
        await self.chan.run(self._conn.close)

    async def cursor(self) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.cursor()
            return ACursor(self.chan, cursor=cursor)

        return await self.chan.run(cont)

    async def iter_dump(self) -> AsyncIterator:
        def co() -> Iterator[str]:
            return self._conn.iterdump()

        it = await self.chan.run(co)

        def cont() -> Optional[str]:
            return next(it, None)

        line = await self.chan.run(cont)
        while line is not None:
            yield line
            line = await self.chan.run(cont)

    async def execute_script(self, script: str) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.executescript(script)
            return ACursor(self.chan, cursor=cursor)

        return await self.chan.run(cont)

    async def commit(self) -> None:
        return await self.chan.run(self._conn.commit)

    async def execute(self, sql: str, params: Iterable[SQL_TYPES] = ()) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.execute(sql, params)
            return ACursor(self.chan, cursor=cursor)

        return await self.chan.run(cont)

    async def execute_many(
        self, sql: str, params: Iterable[Iterable[SQL_TYPES]] = ()
    ) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.executemany(sql, params)
            return ACursor(self.chan, cursor=cursor)

        return await self.chan.run(cont)


def sql_escape(param: str, nono: Set[str], escape: str) -> str:
    def cont() -> Iterator[str]:
        for char in iter(param):
            if char in nono:
                yield escape
            yield char

    return "".join(cont())
