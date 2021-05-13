from dataclasses import dataclass


@dataclass(frozen=True)
class Metrics:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    proximity: int
    prevalence: int
