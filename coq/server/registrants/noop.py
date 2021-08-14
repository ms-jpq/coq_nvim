from dataclasses import dataclass
from itertools import chain
from random import choice, sample
from typing import Sequence, Tuple

from pynvim import Nvim
from std2.pickle import new_decoder
from yaml import safe_load

from ...consts import HELO_ARTIFACTS
from ...registry import rpc
from ..rt_types import Stack


@dataclass(frozen=True)
class _Helo:
    chars: Tuple[int, int]
    cocks: Sequence[str]
    stars: Sequence[str]
    helo: Sequence[str]


_HELO = new_decoder(_Helo)(safe_load(HELO_ARTIFACTS.read_text("UTF-8")))


@rpc(blocking=True)
def now(nvim: Nvim, stack: Stack, *_: str) -> None:
    lo, hi = _HELO.chars
    chars = choice(range(lo, hi))
    star = (choice(_HELO.stars),)
    birds = " ".join(chain(star, sample(_HELO.cocks, k=chars), star))
    helo = choice(_HELO.helo)
    msg = f"{birds}  {helo}"
    print(msg, flush=True)
