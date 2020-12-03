from dataclasses import dataclass
from enum import Enum, auto
from typing import Iterator

from ..shared.chan import Chan
from ..shared.core import run_forever
from ..shared.types import Channel


class State(Enum):
    unitinalized = auto()
    char_inserted = auto()
    comp_inserted = auto()


@dataclass(frozen=True)
class StateChans:
    char_inserted_ch: Channel[None]
    text_changed_ch: Channel[None]
    comp_inserted_ch: Channel[None]
    i_insertable: Iterator[bool]
    p_insertable: Iterator[bool]


def state() -> StateChans:
    char_inserted_ch, text_changed_ch, comp_inserted_ch = (
        Chan[None](),
        Chan[None](),
        Chan[None](),
    )
    state = State.unitinalized

    async def comp_inserted() -> None:
        nonlocal state
        async for _ in char_inserted_ch:
            state = State.char_inserted

    async def text_changed() -> None:
        nonlocal state
        async for _ in text_changed_ch:
            state = State.char_inserted

    async def comp_changed() -> None:
        nonlocal state
        async for _ in comp_inserted_ch:
            state = State.comp_inserted

    def i_insertable() -> Iterator[bool]:
        while True:
            yield True

    def p_insertable() -> Iterator[bool]:
        while True:
            yield state != State.comp_inserted

    run_forever(comp_inserted, text_changed, comp_changed)

    return StateChans(
        char_inserted_ch=char_inserted_ch,
        text_changed_ch=text_changed_ch,
        comp_inserted_ch=comp_inserted_ch,
        i_insertable=i_insertable(),
        p_insertable=p_insertable(),
    )
