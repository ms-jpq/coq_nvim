from contextlib import closing
from itertools import count
from sqlite3 import Connection, Cursor, OperationalError
from threading import Lock
from typing import Iterable, Iterator, Mapping, Sequence, TypedDict

from std2.sqllite3 import with_transaction

from ....consts import SNIPPET_DB
from ....registry import pool
from ....shared.database import init_db
from ....shared.executor import Executor
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
        self._ex = Executor(pool)
        self._conn: Connection = self._ex.submit(_init)
        self._count = count()

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
                for filetype, snippets in mapping.items():
                    with with_transaction(cursor):
                        _ensure_ft(cursor, filetypes=(filetype,))
                        for row_id, snippet in zip(self._count, snippets):
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
                                    {"snippet_id": row_id, "option": option.name},
                                )

        self._ex.submit(cont)

    def select(self, filetype: str, word: str) -> Sequence[_Snip]:
        def cont() -> Sequence[_Snip]:
            def c1() -> Iterator[_Snip]:
                with closing(self._conn.cursor()) as cursor:
                    with with_transaction(cursor):
                        cursor.execute(
                            sql("select", "snippets"),
                            {"filetype": filetype, "word": word},
                        )

                        for row in cursor.fetchall():
                            cursor.execute(
                                sql("select", "matches"),
                                {"snippet_id": row["snippet_id"], "word": word},
                            )
                            snip = _Snip(
                                grammar=row["grammar"],
                                prefix=cursor.fetchone()["match"],
                                snippet=row["content"],
                                label=row["label"],
                                doc=row["doc"],
                            )
                            yield snip

            try:
                return tuple(c1())
            except OperationalError:
                return ()

        self._interrupt()
        return self._ex.submit(cont)

