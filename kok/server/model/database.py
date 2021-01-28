from sqlite3 import Connection

from std2.asqllite3 import AConnection

from .sql import sql


class Database:
    def __init__(self, location: str) -> None:
        self._conn = AConnection(database=location)

    async def init(self) -> None:
        def cont(conn: Connection) -> None:
            conn.executescript(sql("init", "pragma"))
            conn.executescript(sql("init", "tables"))

        await self._conn.with_conn(cont)

    async def vaccum(self) -> None:
        def cont(conn: Connection) -> None:
            conn.executescript(sql("vaccum", "periodical"))

        await self._conn.with_conn(cont)

    async def vaccum(self) -> None:
        def cont(conn: Connection) -> None:
            conn.executescript(sql("vaccum", "periodical"))

        await self._conn.with_conn(cont)