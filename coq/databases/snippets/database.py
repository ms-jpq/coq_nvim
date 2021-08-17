from asyncio import CancelledError
from concurrent.futures import Executor
from contextlib import closing
from sqlite3 import Connection, Cursor, OperationalError
from threading import Lock
from typing import AbstractSet, Iterable, Iterator, Mapping, Sequence, TypedDict, cast
from uuid import uuid4

from std2.asyncio import run_in_executor
from std2.sqlite3 import with_transaction

from ...consts import SNIPPET_DB
from ...shared.executor import SingleThreadExecutor
from ...shared.settings import Options
from ...shared.sql import BIGGEST_INT, init_db
from ...snippets.types import ParsedSnippet
from .sql import sql


class _Snip(TypedDict):
    grammar: str
    prefix: str
    snippet: str
    label: str
    doc: str


def _init() -> Connection:
    conn = Connection(SNIPPET_DB, isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


def _ensure_ft(cursor: Cursor, filetypes: Iterable[str]) -> None:
    def it() -> Iterator[Mapping]:
        for ft in filetypes:
            yield {"filetype": ft}

    cursor.executemany(sql("insert", "filetype"), it())


class SDB:
    def __init__(self, pool: Executor) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    async def add_exts(self, exts: Mapping[str, AbstractSet[str]]) -> None:
        fts = exts.keys() | {v for vs in exts.values() for v in vs}

        def it() -> Iterator[Mapping]:
            for src, dests in exts.items():
                for dest in dests:
                    yield {"src": src, "dest": dest}

        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_ft(cursor, filetypes=fts)
                    cursor.executemany(sql("insert", "extension"), it())

        await run_in_executor(self._ex.submit, cont)

    async def populate(self, mapping: Mapping[str, Iterable[ParsedSnippet]]) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    for filetype, snippets in mapping.items():
                        _ensure_ft(cursor, filetypes=(filetype,))
                        for snippet in snippets:
                            row_id = uuid4().bytes
                            cursor.execute(
                                sql("insert", "snippet"),
                                {
                                    "rowid": row_id,
                                    "filetype": filetype,
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
                            for option in snippet.options:
                                cursor.execute(
                                    sql("insert", "option"),
                                    {"snippet_id": row_id, "option": option},
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
            await run_in_executor(self._interrupt)
            raise
