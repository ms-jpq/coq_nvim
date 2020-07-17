from typing import Optional, Union

from .da import Nil, nil, or_else
from .types import State


def initial() -> State:
    state = State(col=None, done=True)
    return state


def forward(
    state: State, *, col: Union[Optional[int], Nil] = nil, done: Union[bool, Nil] = nil,
) -> State:
    state = State(
        col=or_else(col, state.col),
        done=or_else(done, state.done),
    )
    return state
