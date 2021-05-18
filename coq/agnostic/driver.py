from typing import TypeVar
from uuid import UUID

from pynvim import Nvim

from .datatypes import Context
from .rttypes import Driver
from .settings.types import Options

T_co = TypeVar("T_co", contravariant=True)


class BaseDriver(Driver):
    pass

    def __init__(
        self, nvim: Nvim, options: Options, collector: Collector, extra: T_co
    ) -> None:
        ...

    def collect(self, token: UUID, context: Context) -> None:
        ...
