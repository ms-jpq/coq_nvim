from typing import Literal, Tuple

from pynvim import Nvim

from ...registry import rpc
from ..runtime import Stack


@rpc(blocking=True)
def omnifunc(nvim: Nvim, stack: Stack, args: Tuple[Literal[0, 1], str]) -> int:
    op, _ = args
    assert op == 1
    return -2
