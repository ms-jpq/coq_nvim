from asyncio import CancelledError
from concurrent.futures import Executor
from contextlib import closing
from pathlib import Path, normcase
from sqlite3 import Connection, OperationalError
from threading import Lock
from typing import Iterator, TypedDict, cast

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
from ...shared.timeit import timeit
from ...snippets.types import LoadedSnips
from .sql import sql

_SCHEMA = "v0"


class _Snip(TypedDict):
    grammar: str
    prefix: str
    snippet: str
    label: str
    doc: str


def _init(db_dir: Path) -> Connection:
    db = db_dir / _SCHEMA
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = Connection(db, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class SDB:
    def __init__(self, pool: Executor, vars_dir: Path) -> None:
        db_dir = vars_dir / "clients" / "snippets"
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init, db_dir)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    async def populate(self, loaded: LoadedSnips) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    for src, dests in loaded.exts.items():
                        for dest in dests:
                            cursor.executemany(
                                sql("insert", "filetype"),
                                ({"filetype": src}, {"filetype": dest}),
                            )
                            cursor.execute(
                                sql("insert", "extension"), {"src": src, "dest": dest}
                            )

                    for hashed, snippet in loaded.snippets.items():
                        source_id = normcase(snippet.source).encode("UTF-8")
                        row_id = hashed.encode("UTF-8")
                        cursor.execute(sql("insert", "source"), {"rowid": source_id})
                        cursor.execute(
                            sql("insert", "filetype"), {"filetype": snippet.filetype}
                        )
                        cursor.execute(
                            sql("insert", "snippet"),
                            {
                                "rowid": row_id,
                                "source_id": source_id,
                                "filetype": snippet.filetype,
                                "grammar": snippet.grammar,
                                "content": snippet.content,
                                "label": snippet.label,
                                "doc": snippet.doc,
                            },
                        )

                        for match in snippet.matches:
                            cursor.execute(
                                sql("insert", "match"),
                                {"snippet_id": row_id, "match": match},
                            )

        await run_in_executor(self._ex.submit, cont)

    async def select(
        self, opts: Options, filetype: str, word: str, limitless: int
    ) -> Iterator[_Snip]:
        def cont() -> Iterator[_Snip]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(
                            sql("select", "snippets"),
                            {
                                "exact": opts.exact_matches,
                                "cut_off": opts.fuzzy_cutoff,
                                "look_ahead": opts.look_ahead,
                                "limit": BIGGEST_INT if limitless else opts.max_results,
                                "filetype": filetype,
                                "word": word,
                            },
                        )
                        rows = cursor.fetchall()
                        return (cast(_Snip, row) for row in rows)
            except OperationalError:
                return iter(())

        def step() -> Iterator[_Snip]:
            self._interrupt()
            return self._ex.submit(cont)

        try:
            return await run_in_executor(step)
        except CancelledError:
            with timeit("INTERRUPT !! SNIPPETS"):
                await run_in_executor(self._interrupt)
            raise
