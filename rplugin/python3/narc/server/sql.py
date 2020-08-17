from os.path import dirname, join, realpath
from sqlite3 import Cursor
from typing import Iterator, Optional, Sequence, Tuple

from ..shared.da import slurp
from ..shared.sql import AConnection
from ..shared.types import LEdit, MEdit
from .types import Suggestion

__sql__ = join(dirname(realpath(__file__)), "sql")


_INIT = slurp(join(__sql__, "init.sql"))
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


def query_snippet(cursor: Cursor, snippet_id: int) -> Optional[Tuple[str, str]]:
    cursor.execute(_QUERY_SNIPPET, (snippet_id,))
    if row := cursor.fetchone():
        kind, content = row
        return kind, content
    else:
        return None


def query_ledits(cursor: Cursor, snippet_id: int) -> Sequence[LEdit]:
    cursor.execute(_QUERY_LEDIT, (snippet_id,))
    if row := cursor.fetchall():
        return row
    else:
        return None


def query_medit(cursor: Cursor, snippet_id: int) -> MEdit:
    cursor.execute(_QUERY_LEDIT, (snippet_id,))
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
                (
                    cached,
                    source,
                    source_shortname,
                    label,
                    sortby,
                    kind,
                    doc,
                    ensure_unique,
                    match,
                    match_normalized,
                ) = row
                snip = query_snippet(cursor, suggestions_id)
                ledits = query_ledits(cursor, suggestions_id)
                medit = query_medit(cursor, suggestions_id)
                suggestion = Suggestion(medit=medit, ledits=ledits,)
                yield suggestion

        finally:
            cursor.close()

    def co() -> Sequence[Suggestion]:
        return tuple(cont())

    async with conn.lock:
        return await conn.chan.run(co)
