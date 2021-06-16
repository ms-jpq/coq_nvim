from dataclasses import dataclass
from typing import AbstractSet


@dataclass(frozen=True)
class Display:
    ellipsis: str
    pum_max_len: int


@dataclass(frozen=True)
class Options:
    timeout: float
    transpose_band: int
    unifying_chars: AbstractSet[str]


@dataclass(frozen=True)
class Weights:
    alphabetical: float
    consecutive_matches: float
    count_by_filetype: float
    insertion_order: float
    nearest_neighbour: float
    num_matches: float
    prefix_matches: float


@dataclass(frozen=True)
class Settings:
    display: Display
    match: Options
    weights: Weights

