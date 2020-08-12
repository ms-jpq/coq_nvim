from typing import AsyncIterator, Iterator, Tuple

from ...shared.parse import normalize
from ...shared.sql import AConnection

_INIT = """
DROP TABLE IF EXISTS words;

CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts4(
  word  TEXT NOT NULL UNIQUE,
  nword TEXT NOT NULL
);
"""

_POPULATE = """
INSERT OR IGNORE INTO words(word, nword) VALUES (?, ?)
"""

_QUERY = """
SELECT word, nword FROM words WHERE nword match ? and nword <> ?
"""


async def init(conn: AConnection) -> None:
    async with await conn.execute_script(_INIT):
        pass


async def populate(conn: AConnection, words: Iterator[str]) -> None:
    def cont() -> Iterator[Tuple[str, str]]:
        for word in words:
            yield word, normalize(word)

    async with await conn.execute_many(_POPULATE, cont()):
        pass
    await conn.commit()


async def prefix_query(
    conn: AConnection, ncword: str, prefix_matches: int
) -> AsyncIterator[Tuple[str, str]]:
    match = f"{ncword[:prefix_matches]}*"
    async with await conn.execute(_QUERY, (match, ncword)) as cursor:
        async for row in cursor:
            yield row
