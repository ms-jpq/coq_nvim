from pprint import pformat

from pynvim import Nvim
from pynvim_pp.preview import set_preview

from ...registry import rpc
from ..rt_types import Stack


@rpc(blocking=True)
def stats(nvim: Nvim, stack: Stack, *_: str) -> None:
    stats = stack.idb.stats()
    preview = pformat(stats).splitlines()
    set_preview(nvim, syntax="", preview=preview)

