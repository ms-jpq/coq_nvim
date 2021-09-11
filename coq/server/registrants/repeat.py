from pynvim import Nvim

from ...registry import rpc
from ..rt_types import Stack
from ..state import state


@rpc(blocking=True)
def dot_repeat(nvim: Nvim, stack: Stack) -> None:
    reg = nvim.funcs.getreg(".")
    if not reg:
        inserted = state().repeat
