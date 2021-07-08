from dataclasses import dataclass
from json import loads
from typing import Any, Mapping

from std2.pickle import new_decoder

from ..consts import SNIPPET_ARTIFACTS


@dataclass(frozen=True)
class _Snips:
    extends: Mapping[str, Any]
    snippets: Mapping[str, Any]


_DECODER = new_decoder(_Snips)


SNIPPETS: _Snips = _DECODER(loads(SNIPPET_ARTIFACTS.read_text("UTF-8")))

