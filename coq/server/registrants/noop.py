from itertools import chain
from random import choice, sample

from pynvim import Nvim

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

# http://www.copahabitat.ca/sites/default/files/languagetool.pdf
_HELO = (
    "Aanii",  # Ojibwe
    "Alo",  # Michif
    "Aloha",  # Spongebob
    "Bonjour",  # French
    "Dia dhuit",  # Irish
    "Hallo",  # Germoney
    "Halò",  # Scottish?
    "Hello",  # English
    "Hola",  # Spanish
    "Kwīingu-néewul",  # Lunaapeew
    "Olá",  # Portuguese
    "Sekoh",  # Mohawk
    "Ullaqut",  # Inuktitut
    "Waajiiye",  # Oji-Cree
    "Wâciyê",  # Cree
    "γεια",  # Greek
    "Здраво",  # Serbian
    "Привет",  # Russian
    "שלום",  # Hebrew
    "سلام",  # Persian
    "مرحبا",  # Arabic
    "สวัสดี",  #  Thai
    "你好",  # Chinese
)


@rpc(blocking=True)
def now(nvim: Nvim, stack: Stack, *_: str) -> None:
    helo = choice(_HELO)
    chars = choice(_CHARS)
    star = (choice(_STARS),)
    birds = " ".join(chain(star, sample(_ANNOUNCE, k=chars), star))
    msg = f"{birds}  {helo}"
    print(msg, flush=True)
