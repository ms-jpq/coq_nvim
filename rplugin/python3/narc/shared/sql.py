from __future__ import annotations

from collections.abc import AsyncIterable
from concurrent.futures import ThreadPoolExecutor
from contextlib import AbstractAsyncContextManager
from sqlite3 import Connection, Cursor, Row, connect
from typing import (
    Any,
    AsyncIterator,
    Callable,
    Iterable,
    Iterator,
    Optional,
    Sequence,
    Set,
    TypeVar,
    Union,
)

from .da import run_in_executor

T = TypeVar("T")

SQL_TYPES = Union[int, float, str, bytes, None]


class AsyncExecutor:
    def __init__(self) -> None:
        self.chan = ThreadPoolExecutor(max_workers=1)

    async def run(self, cont: Callable[[], T]) -> T:
        return await run_in_executor(self.chan, cont)

    def submit(self, cont: Callable[[], T]) -> T:
        return self.chan.submit(cont).result()


class ACursor(AbstractAsyncContextManager, AsyncIterable):
    def __init__(self, chan: AsyncExecutor, cursor: Cursor) -> None:
        self.chan = chan
        self.cursor = cursor

    async def __aexit__(self, *_: Any) -> None:
        await self.chan.run(self.cursor.close)

    def __aiter__(self) -> ACursor:
        return self

    async def __anext__(self) -> Row:
        row = await self.fetch_one()
        if row is None:
            raise StopAsyncIteration
        else:
            return row

    async def fetch_one(self) -> Row:
        return await self.chan.run(self.cursor.fetchone)

    async def fetch_all(self) -> Sequence[Row]:
        return await self.chan.run(self.cursor.fetchall)


class AConnection(AbstractAsyncContextManager):
    def __init__(self, database: str = ":memory:") -> None:
        self.chan = AsyncExecutor()

        def cont() -> Connection:
            return connect(database)

        self.conn = self.chan.submit(cont)

    async def __aexit__(self, *_: Any) -> None:
        await self.chan.run(self.conn.close)

    async def cursor(self) -> ACursor:
        def cont() -> ACursor:
            cursor = self.conn.cursor()
            return ACursor(chan=self.chan, cursor=cursor)

        return await self.chan.run(cont)

    async def iter_dump(self) -> AsyncIterator:
        def co() -> Iterator[str]:
            return self.conn.iterdump()

        it = await self.chan.run(co)

        def cont() -> Optional[str]:
            return next(it, None)

        line = await self.chan.run(cont)
        while line is not None:
            yield line
            line = await self.chan.run(cont)

    async def execute_script(self, script: str) -> ACursor:
        def cont() -> ACursor:
            cursor = self.conn.executescript(script)
            return ACursor(chan=self.chan, cursor=cursor)

        return await self.chan.run(cont)

    async def commit(self) -> None:
        return await self.chan.run(self.conn.commit)

    async def execute(self, sql: str, params: Iterable[SQL_TYPES] = ()) -> ACursor:
        def cont() -> ACursor:
            cursor = self.conn.execute(sql, params)
            return ACursor(chan=self.chan, cursor=cursor)

        return await self.chan.run(cont)

    async def execute_many(
        self, sql: str, params: Iterable[Iterable[SQL_TYPES]] = ()
    ) -> ACursor:
        def cont() -> ACursor:
            cursor = self.conn.executemany(sql, params)
            return ACursor(chan=self.chan, cursor=cursor)

        return await self.chan.run(cont)


def sql_escape(param: str, nono: Set[str], escape: str) -> str:
    def cont() -> Iterator[str]:
        for char in iter(param):
            if char in nono:
                yield escape
            yield char

    return "".join(cont())
