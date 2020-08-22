from asyncio import gather, wait
from os.path import dirname, join, realpath
from typing import Iterable, Iterator, List, Sequence

from ..shared.da import slurp
from ..shared.logging import log
from ..shared.parse import normalize
from ..shared.sql import SQL_TYPES, AConnection, sql_escape
from ..shared.types import Context, SEdit
from .fuzzy import fuzzify
from .types import CacheOptions, MatchOptions, Step, Suggestion

__sql__ = join(dirname(realpath(__file__)), "sql")


_PRAGMA = slurp(join(__sql__, "pragma.sql"))
_INIT = slurp(join(__sql__, "init.sql"))
_INIT_FT = slurp(join(__sql__, "init_filetype.sql"))
_POPULATE = slurp(join(__sql__, "populate.sql"))
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


async def populate(
    conn: AConnection, filetype: str, rank: int, suggestions: Sequence[Suggestion]
) -> None:
    def cont() -> Iterator[Iterable[SQL_TYPES]]:
        for suggestion in suggestions:
            match = suggestion.match
            match_normalized = normalize(match)
            values = (
                match,
                filetype,
                match_normalized,
                rank,
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
    conn: AConnection,
    context: Context,
    timeout: float,
    match_opt: MatchOptions,
    cache_opt: CacheOptions,
) -> Sequence[Step]:
    cword, ncword = context.alnums, context.alnums_normalized
    prefix = ncword[: cache_opt.prefix_matches]
    escaped = sql_escape(prefix, nono=LIKE_ESCAPE, escape=ESCAPE_CHAR)
    like_match = f"{escaped}%" if escaped else ""

    steps: List[Step] = []

    async def cont() -> None:
        async with conn.lock:
            async with await conn.execute(
                _QUERY, (context.filetype, like_match, cword)
            ) as cursor:
                rows = await cursor.fetch_all()

        for row in rows:
            match = row["match"]
            sedit = SEdit(new_text=match)
            rank = row["priority"] + cache_opt.rank_penalty
            suggestion = Suggestion(
                position=context.position,
                source=cache_opt.source_name,
                source_shortname=cache_opt.short_name,
                rank=rank,
                label=row["label"],
                sortby=row["sortby"],
                kind=row["kind"],
                doc=row["doc"],
                match=match,
                match_normalized=row["match_normalized"],
                sedit=sedit,
                unique=True,
                medit=None,
                ledits=(),
                snippet=None,
            )
            step = fuzzify(context, suggestion=suggestion, options=match_opt)
            steps.append(step)

    done, pending = await wait((cont(),), timeout=timeout)
    for p in pending:
        p.cancel()
    await gather(*done)

    if pending:
        log.warning("%s", "cache timed out")

    return steps
