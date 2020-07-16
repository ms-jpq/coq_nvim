from typing import Any, Optional, TypeVar, Union, cast

from .types import State

T = TypeVar("T")


def initial() -> State:
    state = State(col=None, char_received=False)
    return state


class Nil:
    def __eq__(self, o: Any) -> bool:
        return type(o) == Nil


nil = Nil()


def or_else(val: Union[T, Nil], default: T) -> T:
    if val == nil:
        return default
    else:
        return cast(T, val)


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
