from os.path import dirname, join, realpath
from sqlite3 import Cursor
from typing import AsyncIterator, Dict, Iterable, Iterator, Optional, Sequence, Tuple

from ..shared.da import slurp
from ..shared.logging import log
from ..shared.parse import normalize
from ..shared.sql import SQL_TYPES, AConnection, sql_escape
from ..shared.types import Completion, LEdit, MEdit, Position, Snippet
from .types import CacheOptions, Suggestion, SourceFactory

__sql__ = join(dirname(realpath(__file__)), "sql")


_INIT = slurp(join(__sql__, "init.sql"))
_INIT_SOURCE = slurp(join(__sql__, "init_source.sql"))
_POPULATE_BATCH = slurp(join(__sql__, "populate_batch.sql"))
_POPULATE_LEDIT = slurp(join(__sql__, "populate_ledit.sql"))
_POPULATE_MEDIT = slurp(join(__sql__, "populate_medit.sql"))
_POPULATE_SNIPPET = slurp(join(__sql__, "populate_snippet.sql"))
_POPULATE_SUGGESTION = slurp(join(__sql__, "populate_suggestion.sql"))
_DEPOPULATE = slurp(join(__sql__, "depopulate.sql"))
_QUERY_SOURCES = slurp(join(__sql__, "query_sources.sql"))
_QUERY_LEDIT = slurp(join(__sql__, "query_ledits.sql"))
_QUERY_MEDIT = slurp(join(__sql__, "query_medit.sql"))
_QUERY_SNIPPET = slurp(join(__sql__, "query_snippet.sql"))
_QUERY_SUGGESTIONS = slurp(join(__sql__, "query_suggestions.sql"))


ESCAPE_CHAR = "!"
LIKE_ESCAPE = {"_", "[", "%"} | {ESCAPE_CHAR}


async def init(conn: AConnection) -> None:
    async with conn.lock:
        async with await conn.execute_script(_INIT):
            pass


async def init_sources(
    conn: AConnection, sources: Dict[str, SourceFactory]
) -> Dict[str, int]:
    def cont() -> Iterator[Iterable[SQL_TYPES]]:
        for name, source in sources.items():
            yield name, source.short_name, source.unique, source.use_cache

    async with conn.lock:
        async with await conn.execute_many(_INIT_SOURCE, cont()):
            pass
        await conn.commit()

    async def co() -> AsyncIterator[Tuple[str, int]]:
        async with conn.lock:
            async with await conn.execute(_QUERY_SOURCES) as cursor:
                rows = await cursor.fetch_all()
                for row in rows:
                    yield row["name"], row["rowid"]

    opts = {key: val async for key, val in co()}
    return opts


async def populate_batch(conn: AConnection, position: Position) -> int:
    async with conn.lock:
        async with await conn.execute(
            _POPULATE_BATCH, (position.row, position.col)
        ) as cursor:
            rowid = cursor.lastrowid
        await conn.commit()
    return rowid


def populate_snippet(cursor: Cursor, suggestions_id: int, snippet: Snippet) -> None:
    cursor.execute(_POPULATE_SNIPPET, (suggestions_id, snippet.kind, snippet.content))


def populate_ledits(
    cursor: Cursor, suggestions_id: int, ledits: Sequence[LEdit]
) -> None:
    def cont() -> Iterator[Iterable[SQL_TYPES]]:
        for ledit in ledits:
            yield suggestions_id, ledit.begin.row, ledit.begin.col, ledit.end.row, ledit.end.col, ledit.new_text

    cursor.executemany(_POPULATE_LEDIT, cont())


def populate_medit(cursor: Cursor, suggestions_id: int, medit: MEdit) -> None:
    cursor.execute(
        _POPULATE_MEDIT,
        (
            suggestions_id,
            medit.old_prefix,
            medit.new_prefix,
            medit.old_suffix,
            medit.new_suffix,
        ),
    )


def parse_match(comp: Completion) -> Tuple[str, str]:
    def cont() -> str:
        if comp.snippet:
            return comp.snippet.match
        elif comp.medit:
            return comp.medit.new_prefix + comp.medit.new_suffix
        elif comp.ledits:
            return next(iter(comp.ledits)).new_text
        else:
            msg = f"No actionable match for - {comp}"
            log.warning("%s", msg)
            return ""

    match = cont()
    normalized = normalize(match)
    return match, normalized


async def populate_suggestions(
    conn: AConnection, batch: int, source: int, completions: Sequence[Completion]
) -> None:
    def cont() -> None:
        c2 = conn._conn
        cursor = c2.cursor()
        try:
            for comp in completions:
                match, match_normalized = parse_match(comp)
                cursor.execute(
                    _POPULATE_SUGGESTION,
                    (
                        batch,
                        source,
                        match,
                        match_normalized,
                        comp.label,
                        comp.sortby,
                        comp.kind,
                        comp.doc,
                    ),
                )
                rowid = cursor.lastrowid
                if comp.medit:
                    populate_medit(cursor, suggestions_id=rowid, medit=comp.medit)
                populate_ledits(cursor, suggestions_id=rowid, ledits=comp.ledits)
                if comp.snippet:
                    populate_snippet(cursor, suggestions_id=rowid, snippet=comp.snippet)
            c2.commit()
        finally:
            cursor.close()

    async with conn.lock:
        await conn.chan.run(cont)


async def depopulate(conn: AConnection) -> None:
    async with conn.lock:
        async with await conn.execute(_DEPOPULATE):
            pass


def query_snippet(cursor: Cursor, suggestions_id: int, match: str) -> Optional[Snippet]:
    cursor.execute(_QUERY_SNIPPET, (suggestions_id,))
    if row := cursor.fetchone():
        kind, content = row
        snippet = Snippet(kind=kind, match=match, content=content)
        return snippet
    else:
        return None


def query_ledits(cursor: Cursor, suggestions_id: int) -> Iterator[LEdit]:
    cursor.execute(_QUERY_LEDIT, (suggestions_id,))
    for row in cursor.fetchall():
        begin = Position(row=row["begin_row"], col=row["begin_col"])
        end = Position(row=row["end_row"], col=row["end_col"])
        new_text = row["text"]
        ledit = LEdit(begin=begin, end=end, new_text=new_text)
        yield ledit


def query_medit(cursor: Cursor, suggestions_id: int) -> Optional[MEdit]:
    cursor.execute(_QUERY_MEDIT, (suggestions_id,))
    if row := cursor.fetchone():
        medit = MEdit(
            old_prefix=row["old_prefix"],
            new_prefix=row["new_prefix"],
            old_suffix=row["old_suffix"],
            new_suffix=row["new_suffix"],
        )
        return medit
    else:
        return None


async def query(
    conn: AConnection, batch: int, ncword: str, options: CacheOptions
) -> Sequence[Suggestion]:
    prefix = ncword[: options.prefix_matches]
    escaped = sql_escape(prefix, nono=LIKE_ESCAPE, escape=ESCAPE_CHAR)

    def cont() -> Iterator[Suggestion]:
        c2 = conn._conn
        cursor = c2.cursor()
        try:
            cursor.execute(_QUERY_SUGGESTIONS, (batch, batch, escaped))
            for row in cursor.fetchall():
                suggestions_id = row["suggestions_id"]
                match = row["match"]
                position = Position(row=row["prow"], col=row["pcol"])
                snippet = query_snippet(
                    cursor, suggestions_id=suggestions_id, match=match
                )
                ledits = query_ledits(cursor, suggestions_id=suggestions_id)
                medit = query_medit(cursor, suggestions_id=suggestions_id)
                suggestion = Suggestion(
                    position=position,
                    source=row["source"],
                    source_shortname=row["source_shortname"],
                    rank=row["priority"],
                    kind=row["kind"],
                    doc=row["doc"],
                    label=row["label"],
                    sortby=row["sortby"],
                    match=match,
                    match_normalized=row["match_normalized"],
                    medit=medit,
                    ledits=tuple(ledits),
                    snippet=snippet,
                    unique=row["unique"],
                )
                yield suggestion

        finally:
            cursor.close()

    def co() -> Sequence[Suggestion]:
        return tuple(cont())

    async with conn.lock:
        return await conn.chan.run(co)
