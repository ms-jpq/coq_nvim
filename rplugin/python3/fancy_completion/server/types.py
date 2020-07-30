from dataclasses import dataclass
from typing import Any, Dict, Optional, Sequence, Set

from ..shared.types import Completion, Factory, LEdit, Position, Seed


@dataclass(frozen=True)
class Notification:
    source: str
    body: Sequence[Any]


@dataclass(frozen=True)
class FuzzyOptions:
    min_match: int
    unifying_chars: Set[str]


@dataclass(frozen=True)
class CacheOptions:
    short_name: str
    band_size: int
    limit: float
    source_name: str = "cache"


@dataclass(frozen=True)
class SourceSpec:
    main: str
    short_name: str
    enabled: bool
    limit: Optional[float]
    timeout: Optional[float]
    rank: Optional[int]
    config: Dict[str, Any]


@dataclass(frozen=True)
class Settings:
    fuzzy: FuzzyOptions
    cache: CacheOptions
    sources: Dict[str, SourceSpec]


@dataclass(frozen=True)
class SourceFactory:
    name: str
    short_name: str
    timeout: float
    limit: float
    rank: float
    seed: Seed
    manufacture: Factory


@dataclass(frozen=True)
class Step:
    source: str
    rank: float
    source_shortname: str
    text: str
    text_normalized: str
    comp: Completion


@dataclass(frozen=True)
class Payload:
    position: Position
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str
    ledits: Sequence[LEdit]


@dataclass(frozen=True)
class State:
    char_inserted: bool
    comp_inserted: bool
    sources: Set[str]
