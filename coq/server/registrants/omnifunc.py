from pynvim import Nvim

from ...registry import rpc
from ..runtime import Stack


@rpc(blocking=True)
def omnifunc(nvim: Nvim, stack: Stack, *args: str) -> None:
    pass
