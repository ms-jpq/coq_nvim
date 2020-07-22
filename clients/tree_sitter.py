from asyncio import Queue
from typing import AsyncIterator

from pynvim import Nvim

from .pkgs.fc_types import Source, Completion, Context, Seed
from .pkgs.nvim import call


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua(
            "fancy_completion_tree_sitter = require 'fancy-completion/tree_sitter'", ()
        )
        return

    return await call(nvim, cont)


# TODO -- waiting on tree sitter to stabilize
async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    await init_lua(nvim)

    async def source(context: Context) -> AsyncIterator[Completion]:
        yield Completion(
            position=context.position,
            old_prefix="",
            new_prefix="",
            old_suffix="",
            new_suffix="",
        )

    return source
