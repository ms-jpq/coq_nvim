from asyncio import Queue
from typing import AsyncIterator, Sequence

from pkgs.nvim import Buffer, call
from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


async def buffer_lines(nvim: Nvim, buffers: Sequence[Buffer]) -> Sequence[str]:
    def cont() -> Sequence[Sequence[str]]:
        lines = tuple(
            line
            for buffer in buffers
            for line in nvim.api.buf_get_lines(buffer, 0, -1, True)
        )
        return lines

    lines = await call(nvim, cont)
    return lines


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="")

    return source
