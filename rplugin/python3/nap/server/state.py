from typing import Optional, Set

from ..shared.da import or_else
from .types import Settings, State


def initial(settings: Settings) -> State:
    sources = {name for name, source in settings.sources.items() if source.enabled}
    return State(char_inserted=False, comp_inserted=False, sources=sources)


def forward(
    state: State,
    *,
    char_inserted: Optional[bool] = None,
    comp_inserted: Optional[bool] = None,
    sources: Optional[Set[str]] = None
) -> State:
    new_state = State(
        char_inserted=or_else(char_inserted, state.char_inserted),
        comp_inserted=or_else(comp_inserted, state.comp_inserted),
        sources=or_else(sources, state.sources),
    )
    return new_state
