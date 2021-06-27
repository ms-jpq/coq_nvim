from dataclasses import dataclass
from typing import Optional, Sequence


@dataclass(frozen=True)
class ReqL2:
    before: str
    after: str
    filename: str
    max_num_results: Optional[int] = None
    region_includes_beginning: bool = False
    region_includes_end: bool = False


@dataclass(frozen=True)
class ReqL1:
    Autocomplete: ReqL2


@dataclass(frozen=True)
class Request:
    request: ReqL1
    version: str


@dataclass(frozen=True)
class _RespL1:
    new_prefix: str
    old_suffix: str
    new_suffix: str
    kind: Optional[int] = None
    detail: Optional[str] = None
    documentation: Optional[str] = None
    deprecated: Optional[bool] = None
    origin: Optional[str] = None


@dataclass(frozen=True)
class Response:
    old_prefix: str
    results: Sequence[_RespL1]
    user_message: Sequence[str] = ()

