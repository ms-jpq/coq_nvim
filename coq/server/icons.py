from dataclasses import replace

from std2.types import never

from ..shared.settings import IconMode, Icons
from ..shared.types import Completion


def iconify(icons: Icons, completion: Completion) -> Completion:
    if not completion.icon_match:
        return completion
    else:
        alias = icons.aliases.get(completion.icon_match, completion.icon_match)
        kind = icons.mappings.get(alias)
        if not kind:
            return completion
        else:
            if icons.mode is IconMode.none:
                return completion
            elif icons.mode is IconMode.short:
                return replace(completion, kind=kind)
            elif icons.mode is IconMode.long:
                new_kind = f"{kind} {completion.kind}" if completion.kind else kind
                return replace(completion, kind=new_kind)
            else:
                never(icons.mode)
