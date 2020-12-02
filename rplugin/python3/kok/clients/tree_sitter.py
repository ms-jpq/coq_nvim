from typing import Any

from pynvim import Nvim

from ..shared.chan import Chan
from ..shared.comm import make_ch
from ..shared.core import run_forever
from ..shared.types import Channel, Completion, Context, Seed, SourceChans
from .pkgs.nvim import call

NAME = "tree_sitter"


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("kok_tree_sitter = require 'kok/tree_sitter'", ())
        return

    return await call(nvim, cont)


# TODO -- waiting on tree sitter to stabilize
async def main(nvim: Nvim, seed: Seed) -> SourceChans:
    send_ch, recv_ch = make_ch(Context, Channel[Completion])

    await init_lua(nvim)

    async def ooda() -> None:
        async for context in send_ch:
            ch = Chan[Completion]()
            await recv_ch.send(ch)

    run_forever(ooda)

    return SourceChans(comm_ch=Chan[Any](), send_ch=send_ch, recv_ch=recv_ch)
