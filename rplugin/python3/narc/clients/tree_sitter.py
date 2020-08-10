from typing import AsyncIterator

from pynvim import Nvim

from ..shared.types import Comm, Completion, Context, Seed, Source
from .pkgs.nvim import call

NAME = "tree_sitter"


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("narc_tree_sitter = require 'narc/tree_sitter'", ())
        return

    return await call(nvim, cont)


# TODO -- waiting on tree sitter to stabilize
async def main(comm: Comm, seed: Seed) -> Source:
    await init_lua(comm.nvim)

    async def source(context: Context) -> AsyncIterator[Completion]:
        yield Completion(
            position=context.position,
            old_prefix="",
            new_prefix="",
            old_suffix="",
            new_suffix="",
        )

    return source
