from dataclasses import dataclass
from enum import Enum
from typing import Any, Iterable, Optional

from pynvim import Nvim
from std2.pickle import encode
from std2.pickle.coders import uuid_encoder


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


def complete(nvim: Nvim, col: int, comp: Iterable[VimCompletion]) -> None:
    serialized = tuple(
        {
            k: v
            for k, v in encode(cmp, encoders=(uuid_encoder,)).items()
            if v is not None
        }
        for cmp in comp
    )

    nvim.funcs.complete(col + 1, serialized)

