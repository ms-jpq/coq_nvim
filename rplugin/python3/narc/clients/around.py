from asyncio import gather
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from ..shared.parse import coalesce, parse_common_affix
from ..shared.sql import AConnection
from ..shared.types import Comm, Completion, Context, MEdit, Position, Seed, Source
from .pkgs.nvim import call
from .pkgs.sql import init, populate, prefix_query

NAME = "around"


@dataclass(frozen=True)
class Config:
    band_size: int
    prefix_matches: int
    max_length: int


async def buffer_chars(nvim: Nvim, band_size: int, pos: Position) -> Sequence[str]:
    def cont() -> Sequence[str]:
        buffer: Buffer = nvim.api.get_current_buf()
        line_count: int = nvim.api.buf_line_count(buffer)
        min_idx, max_idx = (
            max(0, pos.row - band_size),
            min(line_count, pos.row + band_size + 1),
        )
        lines: Sequence[str] = nvim.api.buf_get_lines(buffer, min_idx, max_idx, True)
        return lines

    lines = await call(nvim, cont)
    chars = tuple(char for line in lines for char in chain(line, linesep))
    return chars


async def main(comm: Comm, seed: Seed) -> Source:
    config = Config(**seed.config)
    band_size = config.band_size
    prefix_matches, max_length, unifying_chars = (
        config.prefix_matches,
        config.max_length,
        seed.match.unifying_chars,
    )

    conn = AConnection()

    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        old_prefix = context.alnums_before
        ncword = context.alnums_normalized[:prefix_matches]

        chars, _ = await gather(
            buffer_chars(comm.nvim, band_size=band_size, pos=position), init(conn)
        )
        words = coalesce(chars, max_length=max_length, unifying_chars=unifying_chars)
        await populate(conn, words=words)
        async for word, match_normalized in prefix_query(conn, ncword=ncword):
            _, old_suffix = parse_common_affix(
                context, match_normalized=match_normalized, use_line=False,
            )
            medit = MEdit(
                old_prefix=old_prefix,
                new_prefix=word,
                old_suffix=old_suffix,
                new_suffix="",
            )
            yield Completion(position=position, medit=medit)

    return source
