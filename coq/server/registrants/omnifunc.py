from pynvim import Nvim

from ...registry import rpc
from ..state import State


@rpc(blocking=True)
def omnifunc(nvim: Nvim, state: State, *args: str) -> None:
    pass
