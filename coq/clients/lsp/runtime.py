from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True)
class LSP:
    cmp_item_kind: Mapping[int, str]

