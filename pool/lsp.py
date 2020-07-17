from asyncio import Queue
from itertools import count
from typing import AsyncIterator

from pkgs.nvim import call
from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("fast_comp = require 'fast_comp'", ())

    await call(nvim, cont)


async def ask(nvim: Nvim, uid: int) -> None:
    def cont() -> None:
        nvim.api.exec_lua("fast_comp.list_comp_candidates(...)", (uid,))

    await call(nvim, cont)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    id_gen = count()
    await init_lua(nvim)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        uid = next(id_gen)
        await ask(nvim, uid=uid)
        for _ in range(5):
            yield SourceCompletion(text="OK")

    return source
