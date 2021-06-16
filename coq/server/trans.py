from typing import Iterator, Sequence

from ..shared.nvim.completions import VimCompletion
from ..shared.types import Completion, Context
from .metrics import rank
from .runtime import Stack
from .types import UserData


def _cmp_to_vcmp(context: Context, cmp: Completion) -> VimCompletion[UserData]:
    abbr = cmp.short_label or cmp.label or cmp.primary_edit.new_text
    menu = f"[{cmp.source}]"
    user_data = UserData(
        uid=context.uid,
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
    stack: Stack, context: Context, completions: Sequence[Completion]
) -> Iterator[VimCompletion]:
    ranked = rank(
        options=stack.settings.match,
        weights=stack.settings.weights,
        db=stack.db,
        context=context,
        completions=completions,
    )
    for cmp in ranked:
        yield _cmp_to_vcmp(context, cmp=cmp)

