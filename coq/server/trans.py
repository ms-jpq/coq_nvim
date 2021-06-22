from textwrap import shorten
from typing import Iterator, MutableSet, Sequence

from pynvim import Nvim
from std2.ordinal import clamp

from ..shared.nvim.completions import VimCompletion
from ..shared.types import Completion, Context
from .metrics import rank
from .runtime import Stack
from .types import UserData


def _cmp_to_vcmp(
    context: Context, width: int, ellipsis: str, cmp: Completion
) -> VimCompletion[UserData]:
    abbr = shorten(
        cmp.label or cmp.primary_edit.new_text, width=width, placeholder=ellipsis
    )
    source = f"[{cmp.source}]"
    menu = f"{cmp.kind} {source}" if cmp.kind else source
    user_data = UserData(
        sort_by=cmp.sort_by,
        commit_uid=context.uid,
        primary_edit=cmp.primary_edit,
        secondary_edits=cmp.secondary_edits,
    )
    vcmp = VimCompletion(
        word="",
        empty=1,
        dup=1,
        equal=1,
        abbr=abbr,
        menu=menu,
        info=cmp.doc,
        user_data=user_data,
    )
    return vcmp


def trans(
    nvim: Nvim, stack: Stack, context: Context, completions: Sequence[Completion]
) -> Iterator[VimCompletion]:
    display = stack.settings.display
    _, col = context.position
    width: int = nvim.options["columns"]
    truncate = clamp(1, width - col - display.pum.x_margin, display.pum.x_max_len)

    ranked = rank(
        options=stack.settings.match,
        weights=stack.settings.weights,
        db=stack.bdb,
        context=context,
        completions=completions,
    )
    seen: MutableSet[str] = set()
    for cmp in ranked:
        if cmp.primary_edit.new_text not in seen:
            seen.add(cmp.primary_edit.new_text)
            yield _cmp_to_vcmp(
                context,
                width=truncate,
                ellipsis=display.ellipsis,
                cmp=cmp,
            )

