from itertools import chain
from random import choice, sample

from pynvim import Nvim
from pynvim_pp.lib import write

from ...registry import rpc
from ..state import State

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
def now(nvim: Nvim, state: State, *args: str) -> None:
    chars = choice(_CHARS)
    star = (choice(_STARS),)
    msg = " ".join(chain(star, sample(_ANNOUNCE, k=chars), star))
    write(nvim, msg)
