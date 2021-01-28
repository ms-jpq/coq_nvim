from sqlite3 import Connection
from sqlite3.dbapi2 import Cursor
from typing import AbstractSet, Iterator, Mapping, Sequence

from std2.asqllite3 import AConnection
from std2.sqllite3 import with_transaction

from ...shared.parse import coalesce, normalize
from .sql import sql


def _ensure_file(cursor: Cursor, project: str, file: str, filetype: str) -> None:
    cursor.execute(sql("insert", "project"), {"project": project})
    cursor.execute(sql("insert", "filetype"), {"filetype": filetype})
    cursor.execute(
        sql("insert", "file"),
        {"filename": file, "project": project, "filetype": filetype},
    )


class Database:
    def __init__(self, location: str) -> None:
        self._conn = AConnection(database=location)

    async def init(self) -> None:
        def cont(conn: Connection) -> None:
            conn.executescript(sql("init", "pragma"))
            conn.executescript(sql("init", "tables"))

        await self._conn.with_conn(cont)

    async def set_lines(
        self,
        project: str,
        file: str,
        filetype: str,
        lines: Sequence[str],
        start_idx: int,
        unifying_chars: AbstractSet[str],
    ) -> None:
        def cont(cursor: Cursor) -> Sequence[str]:
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

            with with_transaction(cursor):
                _ensure_file(cursor, project=project, file=file, filetype=filetype)
                cursor.execute(
                    sql("delete", "word_locations"),
                    {"lo": start_idx, "hi": start_idx + len(lines)},
                )
                cursor.executemany(sql("insert", "word"), m1())
                cursor.executemany(sql("insert", "word_location"), m2())

        return await self._conn.with_cursor(cont)

    async def set_insertion(
        self,
        project: str,
        file: str,
        filetype: str,
        prefix: str,
        suffix: str,
        content: str,
    ) -> None:
        def cont(cursor: Cursor) -> None:
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

        await self._conn.with_cursor(cont)

    async def get_suggestions(self, word: str, prefix_len: int) -> Sequence[str]:
        def cont(cursor: Cursor) -> Sequence[str]:
            nword = normalize(word)
            params = {
                "word": nword,
                "lword": nword.casefold(),
                "prefix_len": prefix_len,
            }
            cursor.execute(sql("query", "words_by_prefix"), params)
            return cursor.fetchall()

        return await self._conn.with_cursor(cont)

    async def vaccum(self) -> None:
        def cont(conn: Connection) -> None:
            conn.executescript(sql("vaccum", "periodical"))

        await self._conn.with_conn(cont)