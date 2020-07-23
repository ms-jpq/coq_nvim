from asyncio import Queue
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Dict, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from .pkgs.fc_types import Completion, Context, Seed, Source
from .pkgs.nvim import call
from .pkgs.shared import coalesce, find_matches, normalize


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
    min_length, max_length = config.min_length, config.max_length

    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        old_prefix, old_suffix = context.alnums_before, context.alnums_after
        cword, ncword = context.alnums, context.alnums_normalized

        chars = await buffer_chars(nvim)
        words: Dict[str, str] = {}
        for word in coalesce(chars, min_length=min_length, max_length=max_length):
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
