from asyncio import Queue
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import AsyncIterator, Iterator, List, Sequence, Set

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed
from .pkgs.nvim import call, print


@dataclass(frozen=True)
class Config:
    same_filetype: bool
    min_length: int


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


def coalesce(chars: Sequence[str], config: Config) -> Iterator[str]:
    min_length = config.min_length
    acc: Set[str] = set()
    curr: List[str] = []

    for char in chars:
        if char.isalnum():
            curr.append(char)
        elif curr:
            word = "".join(curr)
            if word not in acc and len(word) >= min_length:
                acc.add(word)
                yield word
            curr = []

    if curr:
        word = "".join(curr)
        if word not in acc:
            yield word


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    config = Config(**seed.config)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        position = feed.position
        old_prefix = feed.context.alnums_before
        b_gen = buf_gen(nvim, config=config, filetype=feed.filetype)
        lines = await buffer_chars(nvim, b_gen)
        for word in coalesce(lines, config=config):
            yield SourceCompletion(
                position=position, old_prefix=old_prefix, new_prefix=word
            )

    return source
