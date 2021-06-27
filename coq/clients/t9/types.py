from dataclasses import dataclass
from typing import Optional, Sequence


@dataclass(frozen=True)
class _ReqL2:
    max_num_results: int
    before: str
    after: str
    filename: str
    region_includes_beginning: bool = False
    region_includes_end: bool = False


@dataclass(frozen=True)
class _ReqL1:
    Autocomplete: _ReqL2


@dataclass(frozen=True)
class Request:
    request: _ReqL1
    version: str = "2.9.2"


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

