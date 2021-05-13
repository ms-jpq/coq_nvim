from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from sqlite3 import Connection
from sqlite3.dbapi2 import Cursor
from typing import AbstractSet, Iterator, Mapping, Sequence, Tuple

from std2.sqllite3 import with_transaction

from ...agnostic.parse import coalesce, normalize
from .sql import sql
from .types import Metrics


def _ensure_file(cursor: Cursor, project: str, file: str, filetype: str) -> None:
    cursor.execute(sql("insert", "project"), {"project": project})
    cursor.execute(sql("insert", "filetype"), {"filetype": filetype})
    cursor.execute(
        sql("insert", "file"),
        {"filename": file, "project": project, "filetype": filetype},
    )


class Database:
    def __init__(self, location: str) -> None:
        self._pool = ThreadPoolExecutor(max_workers=1)
        self._conn = Connection(location)

        def cont() -> None:
            self._conn.executescript(sql("init", "pragma"))
            self._conn.executescript(sql("init", "tables"))

        self._pool.submit(cont).result()

    def vaccum(self) -> None:
        def cont() -> None:
            self._conn.executescript(sql("vaccum", "periodical"))

        self._pool.submit(cont).result()

    def set_lines(
        self,
        project: str,
        file: str,
        filetype: str,
        lines: Sequence[str],
        start_idx: int,
        unifying_chars: AbstractSet[str],
    ) -> None:
        def cont() -> None:
            words = tuple(
                tuple(coalesce(normalize(line), unifying_chars=unifying_chars))
                for line in lines
            )

            def m1() -> Iterator[Mapping]:
                for line in words:
                    for word in line:
                        yield {"word": word, "lword": word.casefold()}

            def m2() -> Iterator[Mapping]:
                for line_num, line in enumerate(words, start=start_idx):
                    for word in line:
                        yield {
                            "word": word,
                            "filename": file,
                            "line_num": line_num,
                        }

            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_file(cursor, project=project, file=file, filetype=filetype)
                    cursor.execute(
                        sql("delete", "word_locations"),
                        {"lo": start_idx, "hi": start_idx + len(lines)},
                    )
                    cursor.executemany(sql("insert", "word"), m1())
                    cursor.executemany(sql("insert", "word_location"), m2())

        self._pool.submit(cont).result()

    def set_insertion(
        self,
        project: str,
        file: str,
        filetype: str,
        prefix: str,
        suffix: str,
        content: str,
    ) -> None:
        def cont() -> None:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    _ensure_file(cursor, project=project, file=file, filetype=filetype)
                    cursor.execute(
                        sql("insert", "insertion"),
                        {
                            "prefix": prefix,
                            "suffix": suffix,
                            "filename": file,
                            "content": content,
                        },
                    )

        self._pool.submit(cont).result()

    def get_suggestions(self, word: str, prefix_len: int) -> Sequence[str]:
        nword = normalize(word)

        def cont() -> Sequence[str]:
            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(
                        sql("query", "words_by_prefix"),
                        {
                            "word": nword,
                            "lword": nword.casefold(),
                            "prefix_len": prefix_len,
                        },
                    )
                    return cursor.fetchall()

        return self._pool.submit(cont).result()

    def gen_metric(self, words: Sequence[str], filetype: str) -> Sequence[Metrics]:
        def m1() -> Iterator[Mapping]:
            for word in words:
                yield {"word": word, "filetype": filetype}

        def m2() -> Iterator[Mapping]:
            for word in words:
                yield {"word": word, "filetype": filetype}

        def cont() -> Tuple[Sequence[int], Sequence[int]]:

            with closing(self._conn.cursor()) as cursor:
                with with_transaction(cursor):
                    cursor.execute(sql("query", "count_words_by_file_lines"), m1())
                    lines = cursor.fetchall()

                    cursor.execute(sql("query", "count_words_by_filetype"), m2())
                    fts = cursor.fetchall()

                    return lines, fts

        lines, fts = self._pool.submit(cont).result()
