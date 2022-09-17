from dataclasses import dataclass
from pathlib import PurePath
from typing import AbstractSet, Optional, Tuple, Union
from uuid import UUID, uuid4

from std2.cell import RefCell
from std2.pathlib import POSIX_ROOT
from std2.types import Void, VoidType

from ..shared.context import EMPTY_CONTEXT
from ..shared.runtime import Metric
from ..shared.settings import Weights
from ..shared.types import Completion, Context, Edit, NvimPos


@dataclass(frozen=True)
class State:
    cwd: PurePath
    pum_width: int
    screen: Tuple[int, int]
    change_id: UUID
    commit_id: UUID
    preview_id: UUID
    nono_bufs: AbstractSet[int]
    context: Context
    last_edit: Metric
    inserted_pos: NvimPos
    pum_location: Optional[int]


_CELL = RefCell(
    State(
        cwd=POSIX_ROOT,
        pum_width=0,
        screen=(0, 0),
        change_id=uuid4(),
        commit_id=uuid4(),
        preview_id=uuid4(),
        nono_bufs=set(),
        context=EMPTY_CONTEXT,
        last_edit=Metric(
            instance=uuid4(),
            label_width=0,
            kind_width=0,
            weight=Weights(
                prefix_matches=0,
                edit_distance=0,
                recency=0,
                proximity=0,
            ),
            weight_adjust=0,
            comp=Completion(
                source="",
                primary_edit=Edit(new_text=""),
                adjust_indent=False,
                always_on_top=False,
                weight_adjust=0,
                label="",
                sort_by="",
                icon_match="",
            ),
        ),
        inserted_pos=(-1, -1),
        pum_location=None,
    )
)


def state(
    cwd: Optional[PurePath] = None,
    pum_width: Optional[int] = None,
    screen: Optional[Tuple[int, int]] = None,
    change_id: Optional[UUID] = None,
    commit_id: Optional[UUID] = None,
    preview_id: Optional[UUID] = None,
    nono_bufs: AbstractSet[int] = frozenset(),
    context: Optional[Context] = None,
    last_edit: Optional[Metric] = None,
    inserted_pos: Optional[NvimPos] = None,
    pum_location: Union[VoidType, Optional[int]] = Void,
) -> State:
    old_state = _CELL.val

    new_state = State(
        cwd=cwd or old_state.cwd,
        pum_width=pum_width or old_state.pum_width,
        screen=screen or old_state.screen,
        change_id=change_id or old_state.change_id,
        commit_id=commit_id or old_state.commit_id,
        preview_id=preview_id or old_state.preview_id,
        nono_bufs=old_state.nono_bufs | nono_bufs,
        context=context or old_state.context,
        last_edit=last_edit or old_state.last_edit,
        inserted_pos=inserted_pos or old_state.inserted_pos,
        pum_location=pum_location
        if not isinstance(pum_location, VoidType)
        else old_state.pum_location,
    )
    _CELL.val = new_state

    return new_state
