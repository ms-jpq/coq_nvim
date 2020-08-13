from typing import AsyncIterator, Iterable, Iterator, Tuple

from ...shared.sql import SQL_TYPES, AConnection

_INIT = """
DROP TABLE IF EXISTS words;

CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts5(
  word,
  nword
);
"""

_POPULATE = """
INSERT OR IGNORE INTO words (word, nword) VALUES (?, lower(?))
"""

_QUERY = """
SELECT word, nword FROM words WHERE nword match ? and nword <> ?
"""


async def init(conn: AConnection) -> None:
    async with await conn.execute_script(_INIT):
        pass


async def populate(conn: AConnection, words: Iterator[str]) -> None:
    def cont() -> Iterator[Iterable[SQL_TYPES]]:
        for word in words:
            yield word, word

    async with await conn.execute_many(_POPULATE, cont()):
        pass
    await conn.commit()


async def prefix_query(
    conn: AConnection, ncword: str, prefix_matches: int
) -> AsyncIterator[Tuple[str, str]]:
    smol = ncword[:prefix_matches]
    if smol:
        match = f"{smol}*"
        async with await conn.execute(_QUERY, (match, ncword)) as cursor:
            async for row in cursor:
                yield row
