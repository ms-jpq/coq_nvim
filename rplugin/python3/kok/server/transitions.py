from .state import forward
from .types import State


def t_i_insertable(state: State) -> bool:
    return True


def t_p_insertable(state: State) -> bool:
    return state.char_inserted and not state.comp_inserted


def t_char_inserted(state: State) -> State:
    return forward(state, char_inserted=True, comp_inserted=False)


def t_text_changed(state: State) -> State:
    return forward(state, char_inserted=False)


def t_comp_inserted(state: State) -> State:
    return forward(state, comp_inserted=True)
