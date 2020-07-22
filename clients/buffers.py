from asyncio import Queue
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Iterator, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from .pkgs.fc_types import Source, Completion, Context, Seed
from .pkgs.nvim import call
from .pkgs.shared import coalesce


@dataclass(frozen=True)
class Config:
    same_filetype: bool
    min_length: int
    max_length: int


def buf_gen(nvim: Nvim, config: Config, filetype: str) -> Iterator[Buffer]:
    buffers: Sequence[Buffer] = nvim.api.list_bufs()
    for buf in buffers:
        if config.same_filetype:
            ft = nvim.api.buf_get_option(buf, "filetype")
            if ft == filetype:
                yield buf
        else:
            yield buf


async def buffer_chars(nvim: Nvim, buf_gen: Iterator[Buffer]) -> Sequence[str]:
    def cont() -> Sequence[str]:
        chars = tuple(
            char
            for buffer in buf_gen
            for line in nvim.api.buf_get_lines(buffer, 0, -1, True)
            for char in chain(line, linesep)
        )
        return chars

    chars = await call(nvim, cont)
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
        b_gen = buf_gen(nvim, config=config, filetype=context.filetype)
        chars = await buffer_chars(nvim, b_gen)

        for word in parse(chars):
            yield Completion(
                position=position,
                old_prefix=old_prefix,
                new_prefix=word,
                old_suffix=old_suffix,
                new_suffix="",
            )

    return source
