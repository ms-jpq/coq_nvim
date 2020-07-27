from typing import Sequence

from .state import forward
from .types import Settings, State


def t_natural_insertable(state: State) -> bool:
    return state.char_inserted and not state.comp_inserted


def t_char_inserted(state: State) -> State:
    return forward(state, char_inserted=True, comp_inserted=False)


def t_text_changed(state: State) -> State:
    return forward(state, char_inserted=False)


def t_comp_inserted(state: State) -> State:
    return forward(state, comp_inserted=True)


def t_set_sources(state: State, settings: Settings, candidates: Sequence[str]) -> State:
    vaild_sources = settings.sources.keys()
    sources = {*candidates} & vaild_sources
    return forward(state, sources=sources)


def t_toggle_sources(
    state: State, settings: Settings, candidates: Sequence[str]
) -> State:
    vaild_sources = settings.sources.keys()
    selection = {*candidates} & vaild_sources
    sources = state.sources ^ selection
    return forward(state, sources=sources)
