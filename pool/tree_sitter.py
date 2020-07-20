from asyncio import Queue
from typing import AsyncIterator

from pynvim import Nvim

from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed


# TODO -- waiting on tree sitter to stabilize
async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        position = feed.position
        yield SourceCompletion(position=position, old_prefix="", new_prefix="")

    return source
