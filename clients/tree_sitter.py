from asyncio import Queue
from typing import AsyncIterator

from pynvim import Nvim

from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed
from .pkgs.nvim import call


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua(
            "fancy_completion_tree_sitter = require 'fancy-completion/tree_sitter'", ()
        )
        return

    return await call(nvim, cont)


# TODO -- waiting on tree sitter to stabilize
async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    await init_lua(nvim)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(
            position=feed.position,
            old_prefix="",
            new_prefix="",
            old_suffix="",
            new_suffix="",
        )

    return source
