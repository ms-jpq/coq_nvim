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
    change_id: UUID
    commit_id: UUID
    context: Context
    inserted: NvimPos


_state = State(
    screen=(0, 0),
    change_id=uuid4(),
    commit_id=uuid4(),
    context=EMPTY_CONTEXT,
    inserted=(-1, -1),
)


def state(
    screen: Optional[Tuple[int, int]] = None,
    change_id: Optional[UUID] = None,
    commit_id: Optional[UUID] = None,
    context: Optional[Context] = None,
    inserted: Optional[NvimPos] = None,
) -> State:
    global _state

    with _LOCK:
        state = State(
            screen=screen or _state.screen,
            change_id=change_id or _state.change_id,
            commit_id=commit_id or _state.commit_id,
            context=context or _state.context,
            inserted=inserted or _state.inserted,
        )
        _state = state

        return state

