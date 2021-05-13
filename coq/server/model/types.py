from dataclasses import dataclass
from typing import Annotated


@dataclass(frozen=True, order=True)
class Metrics:
    prefix_matches: Annotated[int, ""]
    consecutive_matches: Annotated[
        int, "number of matches where at least two chars match consecutively"
    ]

    proximity: Annotated[int, "closest occurrence in same file"]
    prevalence: Annotated[int, "number of occurrences in same filetype"]

    num_matches: Annotated[int, "number of matches in total"]
