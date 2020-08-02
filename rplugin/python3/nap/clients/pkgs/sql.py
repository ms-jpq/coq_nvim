from typing import Iterator
from ...shared.sql import CONN

_INIT = """
CREATE TABLE words (
  word TEXT NOT NULL PRIMARY KEY,
  nword TEXT NOT NULL
)
"""

_POPULATE = """
INSERT OR IGNORE INTO words(word, nword) VALUES (?, ?)
"""

_QUERY = """
SELECT word FROM words WHERE 1=1
"""


async def init(conn: CONN) -> None:
    async with await conn.execute(_INIT):
        pass


async def populate(conn: CONN, words: Iterator[str]) -> None:
    async with await conn.execute(_POPULATE):
        pass


async def query(conn: CONN) -> None:
    async with await conn.execute(_QUERY):
        pass
