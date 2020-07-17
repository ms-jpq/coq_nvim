from typing import AsyncIterator

from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


async def main(nvim: Nvim, seed: SourceSeed) -> Source:
    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="")

    return source
