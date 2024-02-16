from contextlib import closing, suppress
from sqlite3 import Connection, OperationalError
from typing import Iterable, Iterator, Mapping, Tuple

from ....databases.types import DB
from ....shared.settings import MatchOptions
from ....shared.sql import BIGGEST_INT, init_db, like_esc
from .sql import sql


def _init() -> Connection:
    conn = Connection(":memory:", isolation_level=None)
    init_db(conn)
    conn.executescript(sql("create", "pragma"))
    conn.executescript(sql("create", "tables"))
    return conn


class Database(DB):
    def __init__(self) -> None:
        self._conn = _init()

    def insert(self, keys: Iterable[Tuple[bytes, str]]) -> None:
        def m1() -> Iterator[Mapping]:
            for key, word in keys:
                yield {"key": key, "word": word}

        with suppress(OperationalError):
            with self._conn, closing(self._conn.cursor()) as cursor:
                cursor.executemany(sql("insert", "word"), m1())

    def select(
        self, clear: bool, opts: MatchOptions, word: str, sym: str, limitless: int
    ) -> Tuple[Iterator[Tuple[bytes, str]], int]:
        with suppress(OperationalError):
            if clear:
                with self._conn, closing(self._conn.cursor()) as cursor:
                    cursor.execute(sql("delete", "words"))
            else:
                with self._conn, closing(self._conn.cursor()) as cursor:
                    limit = BIGGEST_INT if limitless else opts.max_results
                    cursor.execute(
                        sql("select", "words"),
                        {
                            "exact": opts.exact_matches,
                            "cut_off": opts.fuzzy_cutoff,
                            "look_ahead": opts.look_ahead,
                            "limit": limit,
                            "word": word,
                            "sym": sym,
                            "like_word": like_esc(word[: opts.exact_matches]),
                            "like_sym": like_esc(sym[: opts.exact_matches]),
                        },
                    )
                    rows = cursor.fetchall()
                    return ((row["key"], row["word"]) for row in rows), len(rows)

        return iter(()), 0
