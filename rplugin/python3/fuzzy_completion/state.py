from typing import Optional

from .da import or_else
from .types import State


def initial() -> State:
    return State(char_inserted=False)


def forward(state: State, *, char_inserted: Optional[bool] = None) -> State:
    new_state = State(char_inserted=or_else(char_inserted, state.char_inserted),)
    return new_state
