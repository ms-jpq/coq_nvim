from os.path import dirname, join, realpath
from sqlite3 import Cursor
from typing import Iterator, Optional, Sequence

from ..shared.da import slurp
from ..shared.sql import AConnection
from ..shared.types import LEdit, MEdit, Position, Snippet
from .types import Suggestion

__sql__ = join(dirname(realpath(__file__)), "sql")


_INIT = slurp(join(__sql__, "init.sql"))
_POPULATE_SOURCE = slurp(join(__sql__, "populate_source.sql"))
_POPULATE_BATCH = slurp(join(__sql__, "populate_batch.sql"))
_POPULATE_LEDIT = slurp(join(__sql__, "populate_ledit.sql"))
_POPULATE_MEDIT = slurp(join(__sql__, "populate_medit.sql"))
_POPULATE_SNIPPET = slurp(join(__sql__, "populate_snippet.sql"))
_POPULATE_SNIPPET_KIND = slurp(join(__sql__, "populate_snippet_kind.sql"))
_POPULATE_SUGGESTION = slurp(join(__sql__, "populate_suggestion.sql"))
_DEPOPULATE = slurp(join(__sql__, "depopulate.sql"))
_QUERY_LEDIT = slurp(join(__sql__, "query_ledit"))
_QUERY_MEDIT = slurp(join(__sql__, "query_medit"))
_QUERY_SNIPPET = slurp(join(__sql__, "query_snippet"))
_QUERY_SUGGESTIONS = slurp(join(__sql__, "query_suggestions"))


async def init(conn: AConnection) -> None:
    async with await conn.execute_script(_INIT):
        pass


async def populate_sources(conn: AConnection) -> None:
    pass


async def populate_batch(conn: AConnection) -> None:
    pass


def populate_snippet(cursor: Cursor) -> None:
    pass


def populate_ledits(cursor: Cursor) -> None:
    pass


def populate_medit(cursor: Cursor) -> None:
    pass


async def populate_suggestions(conn: AConnection) -> None:
    pass


async def depopulate(conn: AConnection) -> None:
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


async def query(conn: AConnection, batch: int, ncword: str) -> Sequence[Suggestion]:
    def cont() -> Iterator[Suggestion]:
        c2 = conn._conn
        cursor = c2.cursor()
        try:
            cursor.execute(_QUERY_SUGGESTIONS, (batch, batch, ncword))
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
                    match=match,
                    match_normalized=row["match_normalized"],
                    medit=medit,
                    ledits=tuple(ledits),
                    snippet=snippet,
                )
                yield suggestion

        finally:
            cursor.close()

    def co() -> Sequence[Suggestion]:
        return tuple(cont())

    async with conn.lock:
        return await conn.chan.run(co)
