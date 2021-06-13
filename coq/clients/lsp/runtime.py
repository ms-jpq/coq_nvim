from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True)
class _CmpItemKind:
    lookup: Mapping[int, str]
    default: str


@dataclass(frozen=True)
class LSP:
    cmp_item_kind: _CmpItemKind

