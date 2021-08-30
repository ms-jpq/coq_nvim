from dataclasses import replace

from ..shared.settings import Icons
from ..shared.types import Completion


def iconify(icons: Icons, completion: Completion) -> Completion:
    if not completion.icon_match:
        return completion
    else:
        alias = icons.alias.get(completion.icon_match, completion.icon_match)
        kind = icons.mappings.get(alias)
        if not kind:
            return completion
        else:
            return replace(completion, kind=kind)
