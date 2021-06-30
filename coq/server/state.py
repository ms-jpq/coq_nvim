from dataclasses import dataclass
from threading import Lock
from typing import Optional, Tuple
from uuid import UUID, uuid4

from ..shared.context import EMPTY_CONTEXT
from ..shared.types import Context, NvimPos

_LOCK = Lock()


@dataclass(frozen=True)
class State:
    screen: Tuple[int, int]
    commit: UUID
    context: Context
    request: Optional[NvimPos]
    inserted: Optional[NvimPos]


_state = State(
    screen=(0, 0),
    commit=uuid4(),
    context=EMPTY_CONTEXT,
    request=None,
    inserted=None,
)


def state(
    screen: Optional[Tuple[int, int]] = None,
    commit: Optional[UUID] = None,
    context: Optional[Context] = None,
    request: Optional[NvimPos] = None,
    inserted: Optional[NvimPos] = None,
) -> State:
    global _state

    with _LOCK:
        state = State(
            screen=screen or _state.screen,
            commit=commit or _state.commit,
            context=context or _state.context,
            request=request or _state.request,
            inserted=inserted or _state.inserted,
        )
        _state = state

        return state

