from asyncio import Queue
from typing import AsyncIterator, Iterator, List, Sequence, Set

from pkgs.nvim import Buffer, call
from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


def buf_gen(nvim: Nvim, filetype: str) -> Iterator[Buffer]:
    buffers: Sequence[Buffer] = nvim.api.list_bufs()
    for buf in buffers:
        ft = nvim.api.buf_get_option(buf, "filetype")
        if ft == filetype:
            yield buf


async def buffer_chars(nvim: Nvim, buf_gen: Iterator[Buffer]) -> Sequence[str]:
    def cont() -> Sequence[str]:
        chars = tuple(
            char
            for buffer in buf_gen
            for line in nvim.api.buf_get_lines(buffer, 0, -1, True)
            for char in line
        )
        return chars

    chars = await call(nvim, cont)
    return chars


def coalesce(chars: Sequence[str]) -> Iterator[str]:
    acc: Set[str] = set()
    curr: List[str] = []
    for char in chars:
        if char.isalnum():
            curr.append(char)
        elif curr:
            word = "".join(curr)
            if word not in acc:
                yield word
            acc.add(word)
            curr = []

    if curr:
        word = "".join(curr)
        if word not in acc:
            yield word


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        prefix = feed.prefix
        if prefix:
            pl = len(prefix)
            lines = await buffer_chars(nvim, buf_gen(nvim, filetype=feed.filetype))
            for word in coalesce(lines):
                if word.startswith(prefix) and word != prefix:
                    text = word[pl:]
                    yield SourceCompletion(text=text, label=word)

    return source
