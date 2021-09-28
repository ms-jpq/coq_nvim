from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, TypedDict


class SimpleRawPayload(TypedDict, total=False):
    kind: str
    text: str


class RawPayload(SimpleRawPayload, TypedDict, total=False):
    filename: str
    parent: SimpleRawPayload
    grandparent: SimpleRawPayload


@dataclass(frozen=True)
class SimplePayload:
    kind: str
    text: str


@dataclass(frozen=True)
class Payload(SimplePayload):
    filename: str
    parent: Optional[SimplePayload]
    grandparent: Optional[SimplePayload]
