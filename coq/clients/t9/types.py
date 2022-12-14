from dataclasses import dataclass
from typing import Any, Optional, Sequence, TypedDict


@dataclass(frozen=True)
class ReqL2:
    correlation_id: int
    before: str
    after: str
    filename: str
    region_includes_beginning: bool
    region_includes_end: bool
    max_num_results: Optional[int] = None


@dataclass(frozen=True)
class ReqL1:
    Autocomplete: ReqL2


@dataclass(frozen=True)
class Request:
    request: ReqL1
    version: str


@dataclass(frozen=True)
class RespL1:
    new_prefix: str
    old_suffix: str
    new_suffix: str
    kind: Optional[int] = None


class Response(TypedDict):
    correlation_id: int
    old_prefix: str
    user_message: Sequence[str]
    results: Sequence[Any]
