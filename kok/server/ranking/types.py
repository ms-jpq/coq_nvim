from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True)
class Metric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    density: float
    matches: Mapping[int, str]
    full_match: bool


@dataclass(frozen=True)
class Metric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    proximity: int
    prevalence_same: int
    prevalence_all: int
    density: float