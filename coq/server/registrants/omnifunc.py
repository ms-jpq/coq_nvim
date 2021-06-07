from typing import Literal, Sequence, Tuple, TypedDict, Union

from pynvim import Nvim

from ...registry import rpc
from ..runtime import Stack


class _OmniComp(TypedDict):
    words: Sequence[str]


@rpc(blocking=True)
def omnifunc(
    nvim: Nvim, stack: Stack, args: Tuple[Tuple[Literal[0, 1], str]]
) -> Union[int, _OmniComp]:
    (op, _), *_ = args

    if op == 1:
        return -1
    else:
        words = ("i love", "kfc")
        return {"words": words}
