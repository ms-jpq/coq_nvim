from os.path import dirname, join, realpath
from typing import AsyncIterator, Iterable, Iterator

from ...shared.da import slurp
from ...shared.sql import SQL_TYPES, AConnection, sql_escape
from ...shared.types import Context

__sql__ = join(realpath(dirname(__file__)), "sql")

_PRAGMA = slurp(join(__sql__, "pragma.sql"))
_INIT = slurp(join(__sql__, "init.sql"))
_DEPOPULATE = slurp(join(__sql__, "depopulate.sql"))
_POPULATE = slurp(join(__sql__, "populate.sql"))
_QUERY = slurp(join(__sql__, "query.sql"))


ESCAPE_CHAR = "!"
LIKE_ESCAPE = {"_", "[", "%"} | {ESCAPE_CHAR}


class DB:
    def __init__(self) -> None:
        self._conn = AConnection()

    async def init(self) -> None:
        async with await self._conn.execute_script(_PRAGMA):
            pass
        async with await self._conn.execute_script(_INIT):
            pass

    async def depopulate(self) -> None:
        async with await self._conn.execute(_DEPOPULATE):
            pass

    async def populate(self, words: Iterator[str]) -> None:
        def cont() -> Iterator[Iterable[SQL_TYPES]]:
            for word in words:
                yield word, word

        async with await self._conn.execute_many(_POPULATE, cont()):
            pass
        await self._conn.commit()

    async def query(
        self, context: Context, prefix_matches: int
    ) -> AsyncIterator[str]:
        cword, ncword = context.alnums, context.alnums_normalized
        prefix = ncword[:prefix_matches]
        escaped = sql_escape(prefix, nono=LIKE_ESCAPE, escape=ESCAPE_CHAR)
        match = f"{escaped}%" if escaped else ""

        async with await self._conn.execute(_QUERY, (match, cword)) as cursor:
            rows = await cursor.fetch_all()

        for row in rows:
            yield row["word"]
