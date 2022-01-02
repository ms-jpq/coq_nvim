from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, MutableSequence, Tuple
from uuid import UUID

from pynvim import Nvim
from std2.pickle.encoder import new_encoder

from ..registry import NAMESPACE, atomic
from ..shared.runtime import Metric
from .rt_types import Stack

_LUA = (Path(__file__).resolve(strict=True).parent / "completion.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())


@dataclass(frozen=True)
class VimCompletion:
    user_data: UUID
    abbr: str
    menu: str
    kind: str = ""
    word: str = ""
    equal: int = 1
    dup: int = 1
    empty: int = 1


_ENCODER = new_encoder[VimCompletion](VimCompletion)


def complete(
    nvim: Nvim, stack: Stack, col: int, comps: Iterable[Tuple[Metric, VimCompletion]]
) -> None:
    stack.metrics.clear()

    acc: MutableSequence[Any] = []
    for metric, comp in comps:
        stack.metrics[metric.comp.uid] = metric
        encoded = _ENCODER(comp)
        acc.append(encoded)

    nvim.api.exec_lua(f"{NAMESPACE}.send_comp(...)", (col + 1, acc))
