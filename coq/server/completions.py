from dataclasses import dataclass
from typing import Any, Iterable, MutableSequence, Tuple
from uuid import UUID

from pynvim_pp.nvim import Nvim
from pynvim_pp.types import NoneType
from std2.pickle.encoder import new_encoder

from ..registry import NAMESPACE
from ..shared.runtime import Metric
from .rt_types import Stack


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


async def complete(
    stack: Stack, col: int, comps: Iterable[Tuple[Metric, VimCompletion]]
) -> None:
    stack.metrics.clear()

    acc: MutableSequence[Any] = []
    for metric, comp in comps:
        stack.metrics[metric.comp.uid] = metric
        encoded = _ENCODER(comp)
        acc.append(encoded)

    await Nvim.api.exec_lua(NoneType, f"{NAMESPACE}.send_comp(...)", (col + 1, acc))
