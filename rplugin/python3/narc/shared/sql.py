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


class ACursor(AbstractAsyncContextManager, AsyncIterator):
    def __init__(self, chan: Executor, cursor: Cursor) -> None:
        self._chan = chan
        self._cursor = cursor

    async def __aexit__(self, *_: Any) -> None:
        await self._chan.run(self._cursor.close)

    def __aiter__(self) -> ACursor:
        return self

    async def __anext__(self) -> Row:
        row = await self.fetch_one()
        if row is None:
            raise StopAsyncIteration
        else:
            return row

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
        self.lock = Lock()
        self._chan = Executor()

        def cont() -> Connection:
            return connect(database)

        self._conn = self._chan.run_sync(connect, database).result()

    async def __aexit__(self, *_: Any) -> None:
        await self._chan.run(self._conn.close)

    async def cursor(self) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.cursor()
            return ACursor(self._chan, cursor=cursor)

        return await self._chan.run(cont)

    async def iter_dump(self) -> AsyncIterator:
        def co() -> Iterator[str]:
            return self._conn.iterdump()

        it = await self._chan.run(co)

        def cont() -> Optional[str]:
            return next(it, None)

        line = await self._chan.run(cont)
        while line is not None:
            yield line
            line = await self._chan.run(cont)

    async def execute_script(self, script: str) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.executescript(script)
            return ACursor(self._chan, cursor=cursor)

        return await self._chan.run(cont)

    async def commit(self) -> None:
        return await self._chan.run(self._conn.commit)

    async def execute(self, sql: str, params: Iterable[SQL_TYPES] = ()) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.execute(sql, params)
            return ACursor(self._chan, cursor=cursor)

        return await self._chan.run(cont)

    async def execute_many(
        self, sql: str, params: Iterable[Iterable[SQL_TYPES]] = ()
    ) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.executemany(sql, params)
            return ACursor(self._chan, cursor=cursor)

        return await self._chan.run(cont)


def sql_escape(param: str, nono: Set[str], escape: str) -> str:
    def cont() -> Iterator[str]:
        for char in iter(param):
            if char in nono:
                yield escape
            yield char

    return "".join(cont())
