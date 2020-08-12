from typing import AsyncIterator, Iterator, Tuple

from ...shared.parse import normalize
from ...shared.sql import AConnection

_INIT = """
CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts4(
  word TEXT NOT NULL UNIQUE,
  nword TEXT NOT NULL
)
"""

_DEINIT = """
DROP TABLE IF EXISTS words
"""

_POPULATE = """
INSERT OR IGNORE INTO words(word, nword) VALUES (?, ?)
"""

_QUERY = """
SELECT word, nword FROM words WHERE nword match ? and ncword <> ?
"""


async def init(conn: AConnection) -> None:
    async with await conn.execute(_DEINIT):
        pass
    async with await conn.execute(_INIT):
        pass


async def populate(conn: AConnection, words: Iterator[str]) -> None:
    def cont() -> Iterator[Tuple[str, str]]:
        for word in words:
            yield word, normalize(word)

    async with await conn.execute_many(_POPULATE, cont()):
        pass
    await conn.commit()


async def query(conn: AConnection, ncword: str) -> AsyncIterator[Tuple[str, str]]:
    match = f"{ncword}*"
    async with await conn.execute(_QUERY, (match, ncword)) as cursor:
        async for row in cursor:
            yield row
