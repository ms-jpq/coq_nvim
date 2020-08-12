from __future__ import annotations

from asyncio import get_running_loop
from collections.abc import AsyncIterable
from concurrent.futures import ThreadPoolExecutor
from contextlib import AbstractAsyncContextManager
from sqlite3 import Connection, Cursor, Row, connect
from typing import Any, Callable, Iterable, Sequence, TypeVar

T = TypeVar("T")


class AsyncExecutor:
    def __init__(self) -> None:
        self.loop = get_running_loop()
        self.chan = ThreadPoolExecutor(max_workers=1)

    async def run(self, cont: Callable[[], T]) -> T:
        return await self.loop.run_in_executor(self.chan, cont)

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

    async def create_function(
        self, name: str, num_params: int, func: Callable[..., Any], deterministic: bool
    ) -> None:
        def cont() -> None:
            self.conn.create_function(
                name, num_params, func=func, deterministic=deterministic
            )

        await self.chan.run(cont)

    async def commit(self) -> None:
        return await self.chan.run(self.conn.commit)

    async def execute(self, sql: str, params: Iterable[Any] = ()) -> ACursor:
        def cont() -> ACursor:
            cursor = self.conn.execute(sql, params)
            return ACursor(chan=self.chan, cursor=cursor)

        return await self.chan.run(cont)

    async def execute_many(
        self, sql: str, params: Iterable[Iterable[Any]] = ()
    ) -> ACursor:
        def cont() -> ACursor:
            cursor = self.conn.executemany(sql, params)
            return ACursor(chan=self.chan, cursor=cursor)

        return await self.chan.run(cont)
