from typing import Iterable, Protocol

from pynvim import Nvim

from .datatypes import Completion
from .settings.types import Options


class Collector(Protocol):
    async def add(self, completions: Iterable[Completion]) -> None:
        pass

    def done(self) -> None:
        pass


class Driver(Protocol):
    def __init__(self, nvim: Nvim, options: Options, collector: Collector) -> None:
        pass
