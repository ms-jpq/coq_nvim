from typing import Optional

from ..shared.da import or_else
from .types import State


def forward(
    state: State,
    *,
    char_inserted: Optional[bool] = None,
    comp_inserted: Optional[bool] = None,
) -> State:
    new_state = State(
        char_inserted=or_else(char_inserted, state.char_inserted),
        comp_inserted=or_else(comp_inserted, state.comp_inserted),
    )
    return new_state
