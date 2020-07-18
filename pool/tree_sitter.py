from asyncio import Queue
from typing import AsyncIterator

from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


# TODO -- waiting on tree sitter to stabilize
async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="")

    return source
