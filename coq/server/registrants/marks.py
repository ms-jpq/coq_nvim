from pynvim import Nvim
from pynvim.api.nvim import Nvim

from ...registry import rpc
from ..runtime import Stack


@rpc(blocking=True)
def prev_mark(nvim: Nvim, stack: Stack) -> None:
    pass


@rpc(blocking=True)
def next_mark(nvim: Nvim, stack: Stack) -> None:
    pass

