from asyncio import Queue
from typing import AsyncIterator

from pynvim import Nvim

from ..shared.types import Completion, Context, Seed, Source
from .pkgs.nvim import call

NAME = "tree_sitter"


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua(
            "nap_tree_sitter = require 'nap/tree_sitter'", ()
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
