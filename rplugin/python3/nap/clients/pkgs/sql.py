from typing import AsyncIterator, Iterator, Tuple

from ...shared.parse import normalize
from ...shared.sql import AConnection

_INIT = """
CREATE TABLE words (
  word TEXT NOT NULL UNIQUE,
  nword TEXT NOT NULL
)
"""

_DEINIT = """
DROP TABLE words IF EXISTS
"""

_POPULATE = """
INSERT OR IGNORE INTO words(word, nword) VALUES (?, ?)
"""

_QUERY = """
SELECT word FROM words WHERE count_matches(?, word, nword) >= ?
"""


async def init(conn: AConnection) -> None:
    async with await conn.execute(_INIT):
        pass


async def reinit(conn: AConnection) -> None:
    async with await conn.execute(_DEINIT):
        pass
    async with await conn.execute(_INIT):
        pass


async def populate(conn: AConnection, words: Iterator[str]) -> None:
    def cont() -> Iterator[Tuple[str, str]]:
        for word in words:
            yield word, normalize(word)

    async with await conn.execute_many(_POPULATE, tuple(cont())):
        pass
    await conn.commit()


async def query(conn: AConnection, cword: str, min_match: int) -> AsyncIterator[str]:
    async with await conn.execute(_QUERY, (cword, min_match)) as cursor:
        async for row in cursor:
            yield row[0]
