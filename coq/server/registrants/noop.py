from argparse import Namespace
from dataclasses import dataclass
from itertools import chain
from os import linesep
from random import choice, sample
from sys import stdout
from typing import Sequence, Tuple

from pynvim import Nvim
from pynvim_pp.lib import write
from std2.argparse import ArgparseError, ArgParser
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


_HELO = new_decoder[_Helo](_Helo)(safe_load(HELO_ARTIFACTS.read_text("UTF-8")))


def _parse_args(args: Sequence[str]) -> Namespace:
    parser = ArgParser()
    parser.add_argument("-s", "--shut-up", action="store_true")
    return parser.parse_args(args)


@rpc(blocking=True)
def now(nvim: Nvim, stack: Stack, args: Sequence[str]) -> None:
    try:
        ns = _parse_args(args)
    except ArgparseError as e:
        write(nvim, e, error=True)
    else:
        if not ns.shut_up:
            lo, hi = _HELO.chars
            chars = choice(range(lo, hi))
            star = (choice(_HELO.stars),)
            birds = " ".join(chain(star, sample(_HELO.cocks, k=chars), star))
            helo = choice(_HELO.helo)
            msg = f"{birds}  {helo}{linesep}"
            encoded = msg.encode("UTF-8")
            stdout.buffer.write(encoded)
            stdout.buffer.flush()
