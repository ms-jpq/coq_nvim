from typing import Protocol, Sequence

from ..agnostic.datatypes import Completion


class Reactor(Protocol):
    async def now(self) -> Sequence[Completion]:
        ...
