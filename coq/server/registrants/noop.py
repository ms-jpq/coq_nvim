from itertools import chain
from random import choice, sample

from pynvim import Nvim
from pynvim_pp.lib import write

from ...lang import LANG
from ...registry import rpc
from ..rt_types import Stack

_CHARS = range(2, 6)
_ANNOUNCE = (
    "🥚",
    "🐥",
    "🐣",
    "🐤",
    "🐓",
    "🐔",
)
_STARS = (
    "✨",
    "💫",
    "⭐️",
    "🌟",
)


@rpc(blocking=True)
def now(nvim: Nvim, stack: Stack, *_: str) -> None:
    chars = choice(_CHARS)
    star = (choice(_STARS),)
    birds = " ".join(chain(star, sample(_ANNOUNCE, k=chars), star))
    msg = LANG("welcome", birds=birds)
    write(nvim, msg)

