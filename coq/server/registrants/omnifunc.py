from pynvim import Nvim

from ...registry import rpc


@rpc(blocking=True)
def omnifunc(nvim: Nvim, *_: None) -> None:
    pass
