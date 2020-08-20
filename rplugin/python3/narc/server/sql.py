from os.path import dirname, join, realpath
from typing import AsyncIterator, Dict, Iterable, Iterator, Optional, Sequence, Tuple

from ..shared.da import slurp
from ..shared.parse import normalize
from ..shared.sql import SQL_TYPES, AConnection, sql_escape
from ..shared.types import Completion, Context,  MEdit, Position
from .types import CacheOptions, SourceFactory, Suggestion

__sql__ = join(dirname(realpath(__file__)), "sql")


_PRAGMA = slurp(join(__sql__, "pragma.sql"))
_INIT = slurp(join(__sql__, "init.sql"))
_INIT_FT = slurp(join(__sql__, "init_filetype.sql"))
_POPULATE = slurp(join(__sql__, "populate_suggestions.sql"))
_DEPOPULATE = slurp(join(__sql__, "depopulate.sql"))
_QUERY_FT = slurp(join(__sql__, "query_filetype.sql"))
_QUERY = slurp(join(__sql__, "query_suggestions.sql"))


ESCAPE_CHAR = "!"
LIKE_ESCAPE = {"_", "[", "%"} | {ESCAPE_CHAR}


async def init(conn: AConnection) -> None:
    async with conn.lock:
        async with await conn.execute_script(_PRAGMA):
            pass
        async with await conn.execute_script(_INIT):
            pass


async def depopulate(conn: AConnection) -> None:
    async with conn.lock:
        async with await conn.execute(_DEPOPULATE):
            pass


async def init_filetype(conn: AConnection, filetype: str) -> int:
    async with conn.lock:
        async with await conn.execute(_INIT_FT, (filetype,)):
            pass
        await conn.commit()
        async with await conn.execute(_QUERY_FT, (filetype,)) as cursor:
            row = await cursor.fetch_one()
            return row["rowid"]


async def populate(conn: AConnection, suggestions: Sequence[Suggestion]) -> None:
    def cont() -> Iterator[Iterable[SQL_TYPES]]:
        for suggestion in suggestions:
            yield word, word

    async with conn.lock:
        async with await conn.execute_many(_POPULATE, cont()):
            pass
        await conn.commit()


async def prefix_query(
    conn: AConnection, ncword: str, prefix_matches: int
) -> AsyncIterator[Suggestion]:
    prefix = ncword[:prefix_matches]
    escaped = sql_escape(prefix, nono=LIKE_ESCAPE, escape=ESCAPE_CHAR)
    match = f"{escaped}%" if escaped else ""

    async with conn.lock:
        async with await conn.execute(_QUERY, (match, ncword)) as cursor:
            rows = await cursor.fetch_all()

    for row in rows:
        yield row["word"]
