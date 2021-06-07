from typing import Literal, Sequence, Tuple, TypedDict, Union

from pynvim import Nvim
from pynvim_pp.api import cur_win, win_get_cursor

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
        win = cur_win(nvim)
        _, col = win_get_cursor(nvim, win=win)
        return col
    else:
        words = ("i love", "kfc")
        return {"words": words}
