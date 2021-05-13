from typing import Iterable, Protocol, TypeVar
from uuid import UUID

from pynvim import Nvim

from .datatypes import Completion, Context
from .settings.types import Options

T_co = TypeVar("T_co", contravariant=True)


class Collector(Protocol):
    async def add(self, token: UUID, completions: Iterable[Completion]) -> None:
        ...

    def done(self) -> None:
        ...


class Driver(Protocol[T_co]):
    def __init__(
        self, nvim: Nvim, options: Options, collector: Collector, extra: T_co
    ) -> None:
        ...

    def collect(self, token: UUID, context: Context) -> None:
        ...
