from dataclasses import dataclass
from typing import Mapping

from ..consts import ICON_ARTIFACTS
from ..shared.types import Completion


@dataclass(frozen=True)
class _Icons:
    alias: Mapping[str, str]


_ICONS = _Icons(alias={})


def iconify(completion: Completion) -> Completion:
    if not completion.icon_match:
        return completion
    else:
        alias = _Icons.alias.get(completion.icon_match, completion.icon_match)
        return completion
