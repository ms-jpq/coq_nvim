from typing import Any

from pynvim import Nvim

from ..shared.types import Completion, Context, SEdit, Seed, SourceChans
from .pkgs.nvim import call
from ..shared.chan import Chan
from ..shared.core import run_forever

NAME = "tree_sitter"


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("kok_tree_sitter = require 'kok/tree_sitter'", ())
        return

    return await call(nvim, cont)


# TODO -- waiting on tree sitter to stabilize
async def main(nvim: Nvim, seed: Seed) -> SourceChans:
    send_ch, recv_ch = Chan[Context](), Chan[Completion]()

    await init_lua(nvim)

    async def ooda() -> None:
        async for context in send_ch:
            pos, uuid = context.position, context.uuid
            text = "-- TODO: Waiting for Neovim to stabilize TS --"
            edit = SEdit(new_text=text)
            comp = Completion(uuid=uuid, position=pos, sedit=edit)
            await recv_ch.send(comp)

    run_forever(ooda)

    return SourceChans(comm_ch=Chan[Any](), send_ch=send_ch, recv_ch=recv_ch)
