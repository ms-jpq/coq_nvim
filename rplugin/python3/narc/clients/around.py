from asyncio import gather
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from ..shared.parse import coalesce
from ..shared.sql import AConnection
from ..shared.types import Comm, Completion, Context, Position, SEdit, Seed, Source
from .pkgs.nvim import call
from .pkgs.sql import depopulate, init, populate, prefix_query

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
    await init(conn)

    async def reinit() -> None:
        await depopulate(conn)

    async def source(context: Context) -> AsyncIterator[Completion]:
        position, ncword = context.position, context.alnums_normalized

        chars, _ = await gather(
            buffer_chars(comm.nvim, band_size=band_size, pos=position), reinit()
        )
        words = coalesce(chars, max_length=max_length, unifying_chars=unifying_chars)
        await populate(conn, words=words)
        async for word in prefix_query(
            conn, ncword=ncword, prefix_matches=prefix_matches
        ):
            sedit = SEdit(new_text=word)
            yield Completion(position=position, sedit=sedit)

    return source
