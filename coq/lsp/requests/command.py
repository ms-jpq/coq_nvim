from pynvim import Nvim
from std2.pickle import new_encoder

from ...shared.types import ExternLSP, ExternLUA
from ..types import Command
from .request import async_request

_ENCODER = new_encoder[Command](Command)


async def cmd(nvim: Nvim, extern: ExternLSP) -> None:
    if extern.command:
        name = "lsp_third_party_cmd" if isinstance(extern, ExternLUA) else "lsp_command"
        command = _ENCODER(extern.command)

        clients = {extern.client} if extern.client else set()
        async for _ in async_request(nvim, name, clients, command):
            pass
