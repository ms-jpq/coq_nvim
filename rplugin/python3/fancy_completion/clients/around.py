from asyncio import Queue
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Dict, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from ..shared.parse import coalesce, find_matches, normalize
from ..shared.types import Completion, Context, Position, Seed, Source
from .pkgs.nvim import call

NAME = "around"


@dataclass(frozen=True)
class Config:
    band_size: int
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


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    config = Config(**seed.config)
    band_size = config.band_size
    min_length, max_length, unifying_chars = (
        seed.match.min_match,
        config.max_length,
        seed.match.unifying_chars,
    )

    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        old_prefix, old_suffix = context.alnums_before, context.alnums_after
        cword, ncword = context.alnums, context.alnums_normalized

        chars = await buffer_chars(nvim, band_size=band_size, pos=position)
        words: Dict[str, str] = {}
        for word in coalesce(
            chars, max_length=max_length, unifying_chars=unifying_chars
        ):
            if word not in words:
                words[word] = normalize(word)

        for word in find_matches(
            cword, ncword=ncword, min_match=min_length, words=words
        ):
            yield Completion(
                position=position,
                old_prefix=old_prefix,
                new_prefix=word,
                old_suffix=old_suffix,
                new_suffix="",
            )

    return source
