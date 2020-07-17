from pynvim import Nvim

from .da import nil
from .nvim import call, print
from .state import forward
from .types import State


async def getcol(nvim: Nvim) -> int:
    def cont() -> int:
        window = nvim.api.get_current_win()
        _, col = nvim.api.win_get_cursor(window)
        return col

    return await call(nvim, cont)


def render(state: State) -> bool:
    return state.col is not None and state.char_received


async def t_char_inserted(nvim: Nvim, state: State) -> State:
    await print(nvim, "CHAR INSERTED")
    return forward(state)


async def t_text_changed_i(nvim: Nvim, state: State) -> State:
    await print(nvim, "TEXT CHANGED I")
    col = await getcol(nvim)
    return forward(state, col=col)


async def t_text_changed_p(nvim: Nvim, state: State) -> State:
    await print(nvim, "TEXT CHANGED P")
    return forward(state)


async def t_comp_done(nvim: Nvim, state: State) -> State:
    await print(nvim, "COMP DONE")
    return forward(state, col=nil)
