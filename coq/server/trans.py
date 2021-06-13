from typing import Iterator, Sequence

from ..shared.nvim.completions import VimCompletion
from ..shared.types import Completion, Context
from .metrics import rank
from .runtime import Stack


def _cmp_to_vcmp(cmp: Completion) -> VimCompletion[Completion]:
    abbr = cmp.label or cmp.primary_edit.new_text
    vcmp = VimCompletion(
        word="",
        empty=1,
        dup=1,
        equal=1,
        abbr=abbr,
        menu=cmp.short_label,
        info=cmp.doc,
        user_data=cmp,
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
    yield from map(_cmp_to_vcmp, ranked)
