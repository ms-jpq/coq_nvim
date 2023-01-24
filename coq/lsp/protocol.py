from dataclasses import dataclass
from json import loads
from typing import Mapping, Optional

from pynvim_pp.lib import decode
from std2.pickle.decoder import new_decoder

from ..consts import LSP_ARTIFACTS


@dataclass(frozen=True)
class LSProtocol:
    CompletionItemKind: Mapping[Optional[int], str]
    InsertTextFormat: Mapping[Optional[int], str]


def _load() -> LSProtocol:
    raw = decode(LSP_ARTIFACTS.read_bytes())
    json: Mapping[str, Mapping[str, int]] = loads(raw)
    trans = {key: {v: k for k, v in val.items()} for key, val in json.items()}
    p = new_decoder[LSProtocol](LSProtocol, strict=False)(trans)
    return p


PROTOCOL = _load()
