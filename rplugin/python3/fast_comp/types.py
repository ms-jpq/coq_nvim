from dataclasses import dataclass
from typing import Sequence


@dataclass
class Settings:
    sources: Sequence[str]


@dataclass
class Completion:
    source: str
    display: str
    content: str
