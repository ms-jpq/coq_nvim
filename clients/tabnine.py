from asyncio import Queue
from typing import AsyncIterator, Dict

from pynvim import Nvim

from .pkgs.fc_types import Source, SourceCompletion, SourceFeed, SourceSeed
from .pkgs.nvim import call


async def init_lua(nvim: Nvim) -> Dict[str, int]:
    def cont() -> Dict[str, int]:
        nvim.api.exec_lua("fast_comp_tabnine = require 'fast_comp_lsp'", ())
        entry_kind = nvim.api.exec_lua("return fast_comp_tabnine.list_entry_kind()", ())
        return entry_kind

    return await call(nvim, cont)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    entry_kind = await init_lua(nvim)
    entry_kind_lookup = {v: k for k, v in entry_kind.items()}

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        position = feed.position
        yield SourceCompletion(
            position=position,
            old_prefix="",
            new_prefix="",
            old_suffix="",
            new_suffix="",
        )

    return source
