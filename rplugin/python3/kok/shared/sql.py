from __future__ import annotations

from sqlite3 import Connection, Cursor, Row, connect
from typing import (
    AsyncContextManager,
    Any,
    AsyncIterable,
    AsyncIterator,
    Iterable,
    Iterator,
    Set,
    Union,
)

from .executor import Executor

SQL_TYPES = Union[int, float, str, bytes, None]


class ACursor(AsyncContextManager[ACursor], AsyncIterable[Row]):
    def __init__(self, chan: Executor, cursor: Cursor) -> None:
        self._chan = chan
        self._cursor = cursor

    async def __aexit__(self, *_: Any) -> None:
        await self._chan.run(self._cursor.close)

    def __aiter__(self) -> AsyncIterator[Row]:
        async def cont() -> AsyncIterator[Row]:
            while rows := await self._chan.run(self._cursor.fetchmany):
                for row in rows:
                    yield row

        return cont()

    @property
    def lastrowid(self) -> int:
        return self._cursor.lastrowid

    async def fetch_one(self) -> Row:
        return await self._chan.run(self._cursor.fetchone)


class AConnection(AsyncContextManager[AConnection]):
    def __init__(self, database: str = ":memory:") -> None:
        self.chan = Executor()

        def cont() -> Connection:
            conn = connect(database)
            conn.row_factory = Row
            return conn

        self._conn: Connection = self.chan.run_sync(cont).result()

    async def __aexit__(self, *_: Any) -> None:
        await self.chan.run(self._conn.close)

    async def cursor(self) -> ACursor:
        def cont() -> ACursor:
            cursor = self._conn.cursor()
            return ACursor(self.chan, cursor=cursor)

        return await self.chan.run(cont)

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
