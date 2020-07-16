from typing import Optional

from pynvim import Nvim

from .nvim import call
from .state import forward
from .types import State


async def redraw(nvim: Nvim, state: State) -> bool:
    pass


async def t_on_insert(nvim: Nvim, state: State) -> State:
    def cont() -> Optional[int]:
        pum_open = nvim.funcs.pumvisible() != 0
        if pum_open:
            return None
        else:
            window = nvim.api.get_current_win()
            _, col = nvim.api.win_get_cursor(window)
            return col

    col = await call(nvim, cont)
    return forward(state, col=col)


async def t_on_char(nvim: Nvim, state: State) -> State:
    def cont() -> Optional[int]:
        pum_open = nvim.funcs.pumvisible() != 0
        if pum_open:
            return None
        else:
            window = nvim.api.get_current_win()
            _, col = nvim.api.win_get_cursor(window)
            return col

    col = await call(nvim, cont)
    return forward(state, col=col)
