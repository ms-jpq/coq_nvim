from dataclasses import dataclass
from functools import cached_property
from typing import Annotated, Mapping


@dataclass(frozen=True, order=True)
class Metric:
    prefix_matches: Annotated[int, ""]
    consecutive_matches: Annotated[
        int, "number of matches where at least two chars match consecutively"
    ]

    proximity: Annotated[int, "closest occurrence in same file"]
    prevalence: Annotated[int, "number of occurrences in same filetype"]

    num_matches: Annotated[int, "number of matches in total"]
