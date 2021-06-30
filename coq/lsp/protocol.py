from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True)
class LSProtocol:
    CompletionItemKind: Mapping[str, str]
    InsertTextFormat: Mapping[str, str]

