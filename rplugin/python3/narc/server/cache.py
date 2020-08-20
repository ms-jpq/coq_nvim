from os.path import dirname, join, realpath
from typing import AsyncIterator, Iterable, Iterator, Sequence

from ..shared.da import slurp
from ..shared.parse import normalize
from ..shared.sql import SQL_TYPES, AConnection, sql_escape
from ..shared.types import Context, SEdit
from .types import CacheOptions, Suggestion

__sql__ = join(dirname(realpath(__file__)), "sql")


_PRAGMA = slurp(join(__sql__, "pragma.sql"))
_INIT = slurp(join(__sql__, "init.sql"))
_INIT_FT = slurp(join(__sql__, "init_filetype.sql"))
_POPULATE = slurp(join(__sql__, "populate.sql"))
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


async def populate(
    conn: AConnection, filetype_id: int, suggestions: Sequence[Suggestion]
) -> None:
    def cont() -> Iterator[Iterable[SQL_TYPES]]:
        for suggestion in suggestions:
            match = suggestion.match
            match_normalized = normalize(match)
            values = (
                match,
                filetype_id,
                match_normalized,
                suggestion.label,
                suggestion.sortby,
                suggestion.kind,
                suggestion.doc,
            )
            yield values

    async with conn.lock:
        async with await conn.execute_many(_POPULATE, cont()):
            pass
        await conn.commit()


async def prefix_query(
    conn: AConnection, context: Context, timeout: float, options: CacheOptions,
) -> AsyncIterator[Suggestion]:
    ncword = context.alnums_normalized
    prefix = ncword[: options.prefix_matches]
    escaped = sql_escape(prefix, nono=LIKE_ESCAPE, escape=ESCAPE_CHAR)
    match = f"{escaped}%" if escaped else ""

    async with conn.lock:
        async with await conn.execute(_QUERY, (match, ncword)) as cursor:
            rows = await cursor.fetch_all()

    for row in rows:
        match = row["match"]
        sedit = SEdit(new_text=match)
        suggestion = Suggestion(
            position=context.position,
            label=row["label"],
            sortby=row["sortby"],
            kind=row["kind"],
            doc=row["doc"],
            match=match,
            match_normalized=row["match_normalized"],
            sedit=sedit,
        )
        yield suggestion
