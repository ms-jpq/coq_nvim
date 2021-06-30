from dataclasses import dataclass
from json import loads
from typing import Mapping, Optional

from std2.pickle import decode

from ..consts import LSP_ARTIFACTS


@dataclass(frozen=True)
class LSProtocol:
    CompletionItemKind: Mapping[Optional[int], str]
    InsertTextFormat: Mapping[Optional[int], str]


def _load() -> LSProtocol:
    raw = LSP_ARTIFACTS.read_text("UTF-8")
    json: Mapping[str, Mapping[str, int]] = loads(raw)
    trans = {key: {v: k for k, v in val.items()} for key, val in json.items()}
    p: LSProtocol = decode(LSProtocol, trans)
    return p


PROTOCOL = _load()

