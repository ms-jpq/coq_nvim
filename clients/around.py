from asyncio import Queue
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from .pkgs.fc_types import Completion, Context, Seed, Source
from .pkgs.nvim import call
from .pkgs.shared import coalesce


@dataclass(frozen=True)
class Config:
    band_size: int
    min_length: int
    max_length: int


async def buffer_chars(nvim: Nvim) -> Sequence[str]:
    def cont() -> Sequence[str]:
        buffer: Buffer = nvim.api.get_current_buf()
        lines: Sequence[str] = nvim.api.buf_get_lines(buffer, 0, -1, True)
        return lines

    lines = await call(nvim, cont)
    chars = tuple(char for line in lines for char in chain(line, linesep))
    return chars


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    config = Config(**seed.config)

    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        old_prefix = context.alnums_before
        old_suffix = context.alnums_after
        n_cword = context.alnums_normalized

        parse = coalesce(
            n_cword=n_cword, min_length=config.min_length, max_length=config.max_length
        )
        chars = await buffer_chars(nvim)

        for word in parse(chars):
            yield Completion(
                position=position,
                old_prefix=old_prefix,
                new_prefix=word,
                old_suffix=old_suffix,
                new_suffix="",
            )

    return source
