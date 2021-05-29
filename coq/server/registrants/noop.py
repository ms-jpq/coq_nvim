from random import choice, sample

from pynvim import Nvim
from pynvim_pp.lib import write

from ...registry import rpc

_CHARS = range(3, 6)
_ANNOUNCE = (
    "🥚",
    "🐥",
    "🐣",
    "🐤",
    "🐓",
    "🐔",
)


@rpc(blocking=True)
def now(nvim: Nvim, *_: None) -> None:
    chars = choice(_CHARS)
    msg = " ".join(sample(_ANNOUNCE, k=chars))
    write(nvim, msg)
