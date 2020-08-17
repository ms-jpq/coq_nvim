from os.path import dirname, join, realpath
from sqlite3 import Cursor
from typing import Optional, Sequence, Tuple

from .types import Suggestion
from ..shared.da import slurp
from ..shared.sql import AConnection
from ..shared.types import LEdit, MEdit

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
        old_prefix, new_prefix, old_suffix, new_suffix = row
        medit = MEdit(
            old_prefix=old_prefix,
            new_prefix=new_prefix,
            old_suffix=old_suffix,
            new_suffix=new_suffix,
        )
        return medit
    else:
        return None


async def query(conn: AConnection) -> Suggestion:
    pass
