from typing import Iterator, MutableSet, Sequence

from pynvim import Nvim
from std2.ordinal import clamp

from ..shared.nvim.completions import VimCompletion
from ..shared.settings import PumDisplay
from ..shared.types import Completion, Context
from .metrics import annotate
from .runtime import Stack
from .types import UserData


def _abbr(
    label: str,
    kind: str,
    addendum: int,
    truncate: int,
    max_width: int,
    ellipsis: str,
) -> str:
    rhs = len(kind)
    tr = truncate - rhs

    if len(label) > tr:
        lhs = label[: tr - len(ellipsis)] + ellipsis
    else:
        max_truncated_to = min(max_width + addendum, truncate)
        lhs = label.ljust(max_truncated_to - rhs)

    return lhs + kind


def _cmp_to_vcmp(
    pum: PumDisplay,
    context: Context,
    truncate: int,
    max_width: int,
    cmp: Completion,
) -> VimCompletion:
    (kl, kr), (sl, sr) = pum.kind_context, pum.source_context
    kind = f"{kl}{cmp.kind}{kr}" if cmp.kind else ""
    menu = f"{sl}{cmp.source}{sr}"

    abbr = _abbr(
        cmp.label,
        kind=kind,
        addendum=len(kl) + len(kr) + len(sl) + len(sr),
        truncate=truncate,
        max_width=max_width,
        ellipsis=pum.ellipsis,
    )
    user_data = UserData(
        sort_by=cmp.sort_by,
        commit_uid=context.uid,
        primary_edit=cmp.primary_edit,
        secondary_edits=cmp.secondary_edits,
        doc=cmp.doc,
    )
    vcmp = VimCompletion(
        word="",
        empty=1,
        dup=1,
        equal=1,
        abbr=abbr,
        menu=menu,
        user_data=user_data,
    )
    return vcmp


def trans(
    nvim: Nvim, stack: Stack, context: Context, completions: Sequence[Completion]
) -> Iterator[VimCompletion]:
    display = stack.settings.display
    _, col = context.position
    scr_width: int = nvim.options["columns"]
    truncate = clamp(1, scr_width - col - display.pum.x_margin, display.pum.x_max_len)

    max_width, ranked = annotate(
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
                display.pum,
                context=context,
                truncate=truncate,
                max_width=max_width,
                cmp=cmp,
            )

