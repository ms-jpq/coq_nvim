from typing import Optional, Union

from .da import Nil, nil, or_else
from .types import State


def initial() -> State:
    state = State(col=None, char_received=False)
    return state


def forward(
    state: State,
    *,
    col: Union[Optional[int], Nil] = nil,
    char_received: Union[bool, Nil] = nil,
) -> State:
    state = State(
        col=or_else(col, state.col),
        char_received=or_else(char_received, state.char_received),
    )
    return state
