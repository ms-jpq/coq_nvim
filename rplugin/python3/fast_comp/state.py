from typing import Optional

from .da import or_else
from .types import State


def initial() -> State:
    return State(char_inserted=False, col=-1)


def forward(
    state: State, *, char_inserted: Optional[bool] = None, col: Optional[int] = None
) -> State:
    new_state = State(
        char_inserted=or_else(char_inserted, state.char_inserted),
        col=or_else(col, state.col),
    )
    return new_state
