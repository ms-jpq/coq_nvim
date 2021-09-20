from pynvim import Nvim
from std2.pickle import new_encoder

from ..types import Command
from .request import async_request

_ENCODER = new_encoder[Command](Command)


async def cmd_lsp(nvim: Nvim, cmd: Command) -> None:
    command = _ENCODER(cmd)
    stream = async_request(nvim, "lsp_command", command)
    async for _ in stream:
        pass
