from typing import Optional

from .da import or_else
from .types import State


def initial() -> State:
    state = State(col=-1)
    return state


def forward(state: State, *, col: Optional[int]) -> State:
    state = State(col=or_else(col, state.col))
    return state
