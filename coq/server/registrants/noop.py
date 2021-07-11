from itertools import chain
from random import choice, sample

from pynvim import Nvim
from pynvim_pp.lib import write

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
_HELO = (
    "你好",  # Chinese
    "Hello",  # English
    "Bonjour",  # French
    "Hola",  # Spanish
    "Привет",  # Russian
    "Hallo",  # Germoney
    "Olá",  # Portuguese
    "שלום",  # Hebrew
    "مرحبا",  # Arabic
    "สวัสดี",  #  Thai
    "Здраво",  # Serbian
    "γεια",  # Greek
)


@rpc(blocking=True)
def now(nvim: Nvim, stack: Stack, *_: str) -> None:
    helo = choice(_HELO)
    chars = choice(_CHARS)
    star = (choice(_STARS),)
    birds = " ".join(chain(star, sample(_ANNOUNCE, k=chars), star))
    msg = f"{birds}  {helo}"
    write(nvim, msg)

