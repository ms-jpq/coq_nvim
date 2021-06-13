from dataclasses import asdict, dataclass
from enum import Enum
from typing import Generic, Iterable, Optional, TypeVar

from pynvim import Nvim

T = TypeVar("T")


class VimCompKind(Enum):
    variable = "v"
    function = "f"
    member = "m"
    typedef = "t"
    define = "d"


@dataclass(frozen=True)
class VimCompletion(Generic[T]):
    word: str
    abbr: Optional[str] = None
    menu: Optional[str] = None
    info: Optional[str] = None
    kind: Optional[str] = None
    icase: Optional[int] = None
    equal: Optional[int] = None
    dup: Optional[int] = None
    empty: Optional[int] = None
    user_data: Optional[T] = None


def complete(nvim: Nvim, col: int, comp: Iterable[VimCompletion]) -> None:
    serialized = tuple(
        {k: v for k, v in asdict(cmp).items() if v is not None} for cmp in comp
    )
    nvim.funcs.complete(col, serialized)
