from contextlib import closing
from sqlite3 import Connection, Cursor, OperationalError
from threading import Lock
from typing import Iterable, Iterator, Mapping, Sequence, TypedDict, cast

from std2.sqllite3 import with_transaction

from ....consts import SNIPPET_DB
from ....registry import pool
from ....shared.database import init_db
from ....shared.executor import SingleThreadExecutor
from ....shared.settings import Options
from ....snippets.types import ParsedSnippet
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
    def __init__(self) -> None:
        self._lock = Lock()
        self._ex = SingleThreadExecutor(pool)
        self._conn: Connection = self._ex.submit(_init)

    def _interrupt(self) -> None:
        with self._lock:
            self._conn.interrupt()

    def add_exts(self, exts: Mapping[str, Iterable[str]]) -> None:
        def it() -> Iterator[Mapping]:
            for src, dests in exts.items():
                for dest in dests:
                    yield {"src": src, "dest": dest}

        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_ft(cursor, filetypes=exts)
                    cursor.executemany(sql("insert", "extension"), it())

        self._ex.submit(cont)

    def populate(self, mapping: Mapping[str, Iterable[ParsedSnippet]]) -> None:
        def cont() -> None:
            with self._lock, closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    for filetype, snippets in mapping.items():
                        _ensure_ft(cursor, filetypes=(filetype,))
                        for snippet in snippets:
                            row_id = hash(snippet.grammar + snippet.content)
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

        self._ex.submit(cont)

    def select(self, opts: Options, filetype: str, word: str) -> Sequence[_Snip]:
        def cont() -> Sequence[_Snip]:
            try:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(
                            sql("select", "snippets"),
                            {
                                "exact": opts.exact_matches,
                                "cut_off": opts.fuzzy_cutoff,
                                "filetype": filetype,
                                "word": word,
                            },
                        )
                        return tuple(cast(_Snip, row) for row in cursor.fetchall())
            except OperationalError:
                return ()

        self._interrupt()
        return self._ex.submit(cont)

