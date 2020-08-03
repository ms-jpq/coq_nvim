from asyncio import Queue, as_completed
from dataclasses import dataclass
from os.path import join
from typing import AsyncIterator, Dict, Iterator, Sequence, Tuple

from pynvim import Nvim

from ..shared.consts import __artifacts__
from ..shared.da import slurp
from ..shared.parse import normalize, parse_common_affix
from ..shared.sql import AConnection
from ..shared.types import Completion, Context, Seed, Source

NAME = "dictionary"

__info__ = join(__artifacts__, "dictionary_info.json")
__db__ = join(__artifacts__, "dictionary.db")


@dataclass(frozen=True)
class DictionarySpec:
    path: str
    sep: str


@dataclass(frozen=True)
class Config:
    min_match: int
    sources: Sequence[DictionarySpec]


def read_config(config: Dict[str, Dict[str, str]]) -> Config:
    min_match = config["min_match"]
    sources = tuple(DictionarySpec(**src) for src in config["sources"])
    return Config(min_match=min_match, sources=sources)


async def read_sources(sources: Sequence[DictionarySpec]) -> AsyncIterator[str]:
    async def cont(spec: DictionarySpec) -> Sequence[str]:
        data = await slurp(spec.path)
        return data.split(spec.sep)

    for words in as_completed(tuple(map(cont, sources))):
        for word in await words:
            yield word


_INIT = """
CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts4(
  word TEXT NOT NULL UNIQUE,
  nword TEXT NOT NULL
)
"""


_POPULATE = """
INSERT OR IGNORE INTO words(word, nword) VALUES (?, ?)
"""


_QUERY = """
SELECT word
FROM words
WHERE
    nword MATCH ?
    AND word <> ?
"""


async def init(conn: AConnection) -> None:
    async with await conn.execute(_INIT):
        pass


async def populate(conn: AConnection, words: AsyncIterator[str]) -> None:
    _words = [word async for word in words]

    def cont() -> Iterator[Tuple[str, str]]:
        for word in _words:
            yield word, normalize(word)

    async with await conn.execute_many(_POPULATE, tuple(cont())):
        pass
    await conn.commit()


async def query(
    conn: AConnection, cword: str, ncword: str, min_matches: int
) -> AsyncIterator[str]:
    if len(cword) >= min_matches:
        query = f"{ncword}*"
        async with await conn.execute(_QUERY, (query, cword)) as cursor:
            async for row in cursor:
                yield row[0]


def parse_cword(word: str) -> Tuple[str, str]:
    def cont() -> Iterator[str]:
        for c in reversed(word):
            if c.isalnum():
                yield c
            else:
                break

    cword = "".join(cont())[::-1]
    return cword, normalize(cword)


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    config = read_config(seed.config)
    min_matches = config.min_match
    conn = AConnection()
    await init(conn)
    await populate(conn, words=read_sources(config.sources))

    async def source(context: Context) -> AsyncIterator[Completion]:
        cword, ncword = parse_cword(context.alnums_before)
        async for word in query(
            conn, cword=cword, ncword=ncword, min_matches=min_matches
        ):
            _, old_suffix = parse_common_affix(
                context, match_normalized=ncword, use_line=False,
            )
            yield Completion(
                position=context.position,
                old_prefix=cword,
                new_prefix=word,
                old_suffix=old_suffix,
                new_suffix="",
            )

    return source
