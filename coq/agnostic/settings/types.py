from dataclasses import dataclass
from typing import AbstractSet


@dataclass(frozen=True)
class Options:
    unifying_chars: AbstractSet[str]
    transpose_band: int


@dataclass(frozen=True)
class Weights:
    insertion_order: float
    count_by_filetype: float
    nearest_neighbour: float
    prefix_matches: float
    consecutive_matches: float
    num_matches: float


@dataclass(frozen=True)
class Settings:
    match_options: Options
    metric_weights: Weights
