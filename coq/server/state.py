from dataclasses import dataclass
from threading import Lock
from typing import Optional, Tuple
from uuid import UUID, uuid4

from ..shared.types import Context, NvimPos

_LOCK = Lock()


@dataclass(frozen=True)
class _State:
    screen: Tuple[int, int]
    commit: UUID
    context: Optional[Context]
    request: Optional[NvimPos]
    inserted: Optional[NvimPos]


_state = _State(
    screen=(0, 0),
    commit=uuid4(),
    context=None,
    request=None,
    inserted=None,
)


def state(
    screen: Optional[Tuple[int, int]],
    commit: Optional[UUID],
    context: Optional[Context],
    request: Optional[NvimPos],
    inserted: Optional[NvimPos],
) -> _State:
    global _state

    with _LOCK:
        state = _State(
            screen=screen or _state.screen,
            commit=commit or _state.commit,
            context=context or _state.context,
            request=request or _state.request,
            inserted=inserted or _state.inserted,
        )
        _state = state

        return state

