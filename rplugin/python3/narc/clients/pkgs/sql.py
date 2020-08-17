from os.path import dirname, join, realpath
from typing import AsyncIterator, Iterable, Iterator, Tuple

from ...shared.da import slurp
from ...shared.logging import log
from ...shared.sql import SQL_TYPES, AConnection, sql_escape

__sql__ = join(realpath(dirname(__file__)), "sql")

_INIT = slurp(join(__sql__, "init.sql"))
_DEPOPULATE = slurp(join(__sql__, "depopulate.sql"))
_POPULATE = slurp(join(__sql__, "populate.sql"))
_QUERY = slurp(join(__sql__, "query.sql"))


ESCAPE_CHAR = '"'
MATCH_ESCAPE = set() | {ESCAPE_CHAR}


async def init(conn: AConnection) -> None:
    log.debug("")
    async with conn.lock:
        async with await conn.execute(_INIT):
            pass


async def depopulate(conn: AConnection) -> None:
    async with conn.lock:
        async with await conn.execute(_DEPOPULATE):
            pass


async def populate(conn: AConnection, words: Iterator[str]) -> None:
    def cont() -> Iterator[Iterable[SQL_TYPES]]:
        for word in words:
            yield word, word

    async with conn.lock:
        async with await conn.execute_many(_POPULATE, cont()):
            pass
        await conn.commit()


async def prefix_query(
    conn: AConnection, ncword: str, prefix_matches: int
) -> AsyncIterator[Tuple[str, str]]:
    smol = ncword[:prefix_matches]
    escaped = sql_escape(smol, nono=MATCH_ESCAPE, escape=ESCAPE_CHAR)

    if escaped:
        match = f'"{escaped}"*'

        async with conn.lock:
            async with await conn.execute(_QUERY, (match, ncword)) as cursor:
                rows = await cursor.fetch_all()

        for row in rows:
            yield row
