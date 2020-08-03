from typing import Iterator, Tuple

from ...shared.parse import count_matches, normalize
from ...shared.sql import AConnection

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
SELECT word FROM words WHERE count_matches(?, word, nword) >= ?
"""


async def init(conn: AConnection) -> None:
    async with await conn.execute(_INIT):
        pass
    await conn.create_function(
        "count_matches", num_params=3, func=count_matches, deterministic=True
    )


async def populate(conn: AConnection, words: Iterator[str]) -> None:
    def cont() -> Iterator[Tuple[str, str]]:
        for word in words:
            yield word, normalize(word)

    async with await conn.execute(_POPULATE, tuple(cont())):
        pass
    await conn.commit()


async def query(conn: AConnection) -> None:
    async with await conn.execute(_QUERY):
        pass
