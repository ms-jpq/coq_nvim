from dataclasses import dataclass
from typing import AbstractSet


@dataclass(frozen=True)
class Options:
    unifying_chars: AbstractSet[str]


@dataclass(frozen=True)
class Settings:
    match_options: Options
