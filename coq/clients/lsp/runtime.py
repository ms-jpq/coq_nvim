from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True)
class CmpItemKindLookup:
    lookup: Mapping[int, str]
    default: str

