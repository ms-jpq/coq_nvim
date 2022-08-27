from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Tuple, TypedDict


class SimpleRawPayload(TypedDict, total=False):
    kind: str
    text: str


class RawPayload(SimpleRawPayload, TypedDict, total=False):
    range: Tuple[int, int]
    parent: SimpleRawPayload
    grandparent: SimpleRawPayload


@dataclass(frozen=True)
class SimplePayload:
    kind: str
    text: str


@dataclass(frozen=True)
class Payload(SimplePayload):
    filename: str
    lo: int
    hi: int
    parent: Optional[SimplePayload]
    grandparent: Optional[SimplePayload]
