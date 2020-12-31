from dataclasses import asdict, dataclass
from enum import Enum
from os import linesep
from typing import Any, Mapping, Iterable, Iterator, Optional
from uuid import uuid4

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.common import NvimError


class VimCompKind(Enum):
    variable = "v"
    function = "f"
    member = "m"
    typedef = "t"
    define = "d"


@dataclass(frozen=True)
class VimCompletion:
    word: str
    abbr: Optional[str] = None
    menu: Optional[str] = None
    info: Optional[str] = None
    kind: Optional[str] = None
    icase: Optional[int] = None
    equal: Optional[int] = None
    dup: Optional[int] = None
    empty: Optional[int] = None
    user_data: Optional[Any] = None


def _serialize(comp: VimCompletion) -> Mapping[str, Any]:
    serialized = {k: v for k, v in asdict(comp).items() if v is not None}
    return serialized


async def complete(nvim: Nvim, col: int, comp: Iterator[VimCompletion]) -> None:
    serialized = tuple(map(_serialize, comp))

    def cont() -> None:
        try:
            nvim.funcs.complete(col, serialized)
        except NvimError:
            pass

    await call(nvim, cont)
