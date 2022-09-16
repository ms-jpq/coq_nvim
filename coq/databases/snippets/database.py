from os.path import normcase
from pathlib import Path, PurePath
from sqlite3 import Connection, OperationalError
from typing import AbstractSet, Iterator, Mapping, TypedDict, cast
from uuid import uuid4

from std2.sqlite3 import with_transaction

from ...shared.executor import SingleThreadExecutor
from ...shared.settings import MatchOptions
from ...shared.sql import BIGGEST_INT, init_db, like_esc
from ...snippets.types import LoadedSnips
from ..types import Interruptible
from .sql import sql

_SCHEMA = "v4"


class _Snip(TypedDict):
    grammar: str
    word: str
    snippet: str
    label: str
    doc: str


def _init(db_dir: Path) -> Connection:
    db = (db_dir / _SCHEMA).with_suffix(".sqlite3")
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = Connection(db, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class SDB(Interruptible):
    def __init__(self, vars_dir: Path) -> None:
        db_dir = vars_dir / "clients" / "snippets"
        self._ex = SingleThreadExecutor()
        self._conn: Connection = self._ex.ssubmit(lambda: _init(db_dir))

    async def clean(self, paths: AbstractSet[PurePath]) -> None:
        def cont() -> None:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
                cursor.executemany(
                    sql("delete", "source"),
                    ({"filename": normcase(path)} for path in paths),
                )

        await self._ex.submit(cont)

    async def mtimes(self) -> Mapping[PurePath, float]:
        def cont() -> Mapping[PurePath, float]:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
                cursor.execute(sql("select", "sources"), ())
                return {
                    PurePath(row["filename"]): row["mtime"] for row in cursor.fetchall()
                }

        return await self._ex.submit(cont)

    async def populate(self, path: PurePath, mtime: float, loaded: LoadedSnips) -> None:
        def cont() -> None:
            with self._lock, with_transaction(self._conn.cursor()) as cursor:
                filename, source_id = normcase(path), uuid4().bytes
                cursor.execute(sql("delete", "source"), {"filename": filename})
                cursor.execute(
                    sql("insert", "source"),
                    {"rowid": source_id, "filename": filename, "mtime": mtime},
                )

                for src, dests in loaded.exts.items():
                    for dest in dests:
                        cursor.executemany(
                            sql("insert", "filetype"),
                            ({"filetype": src}, {"filetype": dest}),
                        )
                        cursor.execute(
                            sql("insert", "extension"),
                            {"source_id": source_id, "src": src, "dest": dest},
                        )

                for uid, snippet in loaded.snippets.items():
                    snippet_id = uid.bytes
                    cursor.execute(
                        sql("insert", "filetype"), {"filetype": snippet.filetype}
                    )
                    cursor.execute(
                        sql("insert", "snippet"),
                        {
                            "rowid": snippet_id,
                            "source_id": source_id,
                            "filetype": snippet.filetype,
                            "grammar": snippet.grammar.name,
                            "content": snippet.content,
                            "label": snippet.label,
                            "doc": snippet.doc,
                        },
                    )
                    for match in snippet.matches:
                        cursor.execute(
                            sql("insert", "match"),
                            {"snippet_id": snippet_id, "word": match},
                        )
                cursor.execute("PRAGMA optimize", ())

        await self._ex.submit(cont)

    async def select(
        self, opts: MatchOptions, filetype: str, word: str, sym: str, limitless: int
    ) -> Iterator[_Snip]:
        def cont() -> Iterator[_Snip]:
            try:
                with with_transaction(self._conn.cursor()) as cursor:
                    cursor.execute(
                        sql("select", "snippets"),
                        {
                            "cut_off": opts.fuzzy_cutoff,
                            "look_ahead": opts.look_ahead,
                            "limit": BIGGEST_INT if limitless else opts.max_results,
                            "filetype": filetype,
                            "word": word,
                            "sym": sym,
                            "like_word": like_esc(word[: opts.exact_matches]),
                            "like_sym": like_esc(sym[: opts.exact_matches]),
                        },
                    )
                    rows = cursor.fetchall()
                    return (cast(_Snip, row) for row in rows)
            except OperationalError:
                return iter(())

        with self._interruption():
            return await self._ex.submit(cont)
