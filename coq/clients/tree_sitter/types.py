from dataclasses import dataclass
from typing import Sequence


@dataclass(frozen=True)
class Payload:
    kind: str
    text: str


Msg = Sequence[Payload]

