from itertools import count
from typing import AsyncIterator

from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


async def main(nvim: Nvim, seed: SourceSeed) -> Source:

    it = count()

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        for _ in range(5):
            yield SourceCompletion(text=str(next(it)))

    return source
