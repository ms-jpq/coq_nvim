from asyncio import Queue
from typing import AsyncIterator

from pynvim import Nvim

from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(
            position=feed.position,
            old_prefix="",
            new_prefix="",
            old_suffix="",
            new_suffix="",
        )

    return source
