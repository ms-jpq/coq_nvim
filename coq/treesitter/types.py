from dataclasses import dataclass
from typing import TypedDict


class RawPayload(TypedDict):
    kind: str
    text: str


@dataclass(frozen=True)
class Payload:
    kind: str
    text: str

