from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, MutableSequence, Tuple

from pynvim import Nvim
from std2.pickle import new_encoder

from ..registry import atomic
from ..shared.runtime import Metric
from .rt_types import Stack

_LUA = (Path(__file__).resolve().parent / "completion.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())


@dataclass(frozen=True)
class VimCompletion:
    user_data: str
    abbr: str
    menu: str
    kind: str = ""
    word: str = ""
    equal: int = 1
    dup: int = 1
    empty: int = 1


_ENCODER = new_encoder[VimCompletion](VimCompletion)


def complete(
    nvim: Nvim, stack: Stack, col: int, comp: Iterable[Tuple[Metric, VimCompletion]]
) -> None:
    stack.metrics.clear()
    serialized: MutableSequence[Any] = []
    for m, c in comp:
        stack.metrics[m.comp.uid] = m
        s = _ENCODER(c)
        serialized.append(s)

    nvim.api.exec_lua(_LUA, (col + 1, serialized))
