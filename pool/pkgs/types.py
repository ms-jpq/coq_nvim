from dataclasses import dataclass
from typing import Any, Optional


@dataclass(frozen=True)
class SourceSeed:
    config: Optional[Any] = None


@dataclass(frozen=True)
class SourceCompletion:
    text: str
    display: Optional[str] = None
    preview: Optional[str] = None
