from pynvim import Nvim

from .state import forward
from .types import State


def getcol(nvim: Nvim) -> int:
    window = nvim.api.get_current_win()
    _, col = nvim.api.win_get_cursor(window)
    return col


async def char_inserted(nvim: Nvim, state: State) -> State:
    return forward(state)


async def text_changed(nvim: Nvim, state: State) -> State:
    return forward(state)


async def comp_done(nvim: Nvim, state: State) -> State:
    return forward(state)
