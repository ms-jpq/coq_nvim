from dataclasses import dataclass
from threading import Lock
from typing import Optional, Tuple
from uuid import UUID, uuid4

from ..shared.context import EMPTY_CONTEXT
from ..shared.types import Context, NvimPos


@dataclass(frozen=True)
class State:
    screen: Tuple[int, int]
    change_id: UUID
    commit_id: UUID
    preview_id: UUID
    context: Context
    inserted: NvimPos
    pum_location: int


_LOCK = Lock()


_state = State(
    screen=(0, 0),
    change_id=uuid4(),
    commit_id=uuid4(),
    preview_id=uuid4(),
    context=EMPTY_CONTEXT,
    inserted=(-1, -1),
    pum_location=-1,
)


def state(
    screen: Optional[Tuple[int, int]] = None,
    change_id: Optional[UUID] = None,
    commit_id: Optional[UUID] = None,
    preview_id: Optional[UUID] = None,
    context: Optional[Context] = None,
    inserted: Optional[NvimPos] = None,
    pum_location: Optional[int] = None,
) -> State:
    global _state

    with _LOCK:
        state = State(
            screen=screen or _state.screen,
            change_id=change_id or _state.change_id,
            commit_id=commit_id or _state.commit_id,
            preview_id=preview_id or _state.preview_id,
            context=context or _state.context,
            inserted=inserted or _state.inserted,
            pum_location=pum_location
            if pum_location is not None
            else _state.pum_location,
        )
        _state = state

        return state

