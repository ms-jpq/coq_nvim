from itertools import count
from typing import AsyncIterator

from pkgs.nvim import call
from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("fast_comp = require 'fast_comp'", ())

    await call(nvim, cont)


async def something(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("fast_comp.list_comp_candidates()")

    await call(nvim, cont)


async def main(nvim: Nvim, seed: SourceSeed) -> Source:

    await init_lua(nvim)
    it = count()

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        await something(nvim)
        for _ in range(5):
            yield SourceCompletion(text=str(next(it)))

    return source
