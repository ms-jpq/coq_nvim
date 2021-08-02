from dataclasses import dataclass
from threading import Lock
from typing import AbstractSet, Optional, Tuple, Union
from uuid import UUID, uuid4

from std2.types import Void, VoidType

from ..shared.context import EMPTY_CONTEXT
from ..shared.types import Context, NvimPos


@dataclass(frozen=True)
class State:
    screen: Tuple[int, int]
    change_id: UUID
    commit_id: UUID
    preview_id: UUID
    nono_bufs: AbstractSet[int]
    context: Context
    inserted: NvimPos
    pum_location: Optional[int]


_LOCK = Lock()


_state = State(
    screen=(0, 0),
    change_id=uuid4(),
    commit_id=uuid4(),
    preview_id=uuid4(),
    nono_bufs=set(),
    context=EMPTY_CONTEXT,
    inserted=(-1, -1),
    pum_location=None,
)


def state(
    screen: Optional[Tuple[int, int]] = None,
    change_id: Optional[UUID] = None,
    commit_id: Optional[UUID] = None,
    preview_id: Optional[UUID] = None,
    nono_bufs: AbstractSet[int] = frozenset(),
    context: Optional[Context] = None,
    inserted: Optional[NvimPos] = None,
    pum_location: Union[VoidType, Optional[int]] = Void,
) -> State:
    global _state

    with _LOCK:
        state = State(
            screen=screen or _state.screen,
            change_id=change_id or _state.change_id,
            commit_id=commit_id or _state.commit_id,
            preview_id=preview_id or _state.preview_id,
            nono_bufs=_state.nono_bufs | nono_bufs,
            context=context or _state.context,
            inserted=inserted or _state.inserted,
            pum_location=pum_location
            if not isinstance(pum_location, VoidType)
            else _state.pum_location,
        )
        _state = state

        return state
