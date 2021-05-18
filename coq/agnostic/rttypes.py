from abc import abstractmethod
from concurrent.futures import ThreadPoolExecutor
from typing import Iterable, Protocol, Sequence, TypeVar
from uuid import UUID

from pynvim import Nvim

from .datatypes import Completion, Context
from .settings.types import Options

T_co = TypeVar("T_co", contravariant=True)


class Supervisor(Protocol):
    @property
    @abstractmethod
    def options(self) -> Options:
        ...

    @property
    @abstractmethod
    def nvim(self) -> Nvim:
        ...

    @property
    @abstractmethod
    def pool(self) -> ThreadPoolExecutor:
        ...

    def add(self, token: UUID, completions: Iterable[Completion]) -> None:
        ...

    def report(self) -> Sequence[Completion]:
        ...


class Worker(Protocol[T_co]):
    def __init__(self, supervisor: Supervisor, extra: T_co) -> None:
        ...

    def notify(self, token: UUID, context: Context) -> None:
        ...
