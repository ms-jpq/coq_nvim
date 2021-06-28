from dataclasses import asdict
from itertools import chain
from locale import strxfrm
from typing import Any, Callable, Iterable, Iterator, MutableSet, Sequence, Tuple, cast

from std2.ordinal import clamp

from ..shared.nvim.completions import VimCompletion
from ..shared.parse import display_width
from ..shared.runtime import Metric
from ..shared.settings import Options, PumDisplay, Weights
from ..shared.types import Completion, Context, SnippetEdit
from .runtime import Stack
from .types import UserData

_ZERO = Weights(
    consecutive_matches=0,
    count_by_filetype=0,
    insertion_order=0,
    match_density=0,
    nearest_neighbour=0,
    num_matches=0,
    prefix_matches=0,
)


def _cum(adjustment: Weights, metrics: Iterable[Metric]) -> Tuple[int, Weights]:
    acc = asdict(_ZERO)
    max_width = 0
    for metric in metrics:
        for key, val in asdict(metric.weight).items():
            acc[key] += val
    for key, val in asdict(adjustment).items():
        if val:
            acc[key] /= val
        else:
            acc[key] = 0
    return max_width, Weights(**acc)


def _sort_by(adjustment: Weights) -> Callable[[Metric], Any]:
    adjust = asdict(adjustment)

    def key_by(metric: Metric) -> Any:
        tot = sum(
            val / adjust[key] if adjust[key] else 0
            for key, val in asdict(metric.weight).items()
        )
        return (
            -round(tot * 1000),
            -len(metric.comp.secondary_edits),
            -(metric.comp.doc is not None),
            -isinstance(metric.comp.primary_edit, SnippetEdit),
            metric.comp.tie_breaker,
            strxfrm(metric.comp.sort_by or metric.comp.primary_edit.new_text),
        )

    return key_by


def _abbr(
    label: str,
    kind: str,
    dead_spaces: int,
    truncate: int,
    max_width: int,
    ellipsis: str,
) -> str:
    rhs = len(kind)
    tr = truncate - rhs

    if len(label) > tr:
        lhs = label[: tr - len(ellipsis)] + ellipsis
    else:
        max_truncated_to = min(max_width + dead_spaces, truncate)
        lhs = label.ljust(max_truncated_to - rhs)

    return lhs + kind


def _cmp_to_vcmp(
    pum: PumDisplay,
    context: Context,
    dead_spaces: int,
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
        dead_spaces=dead_spaces,
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
    stack: Stack, context: Context, metrics: Sequence[Metric]
) -> Iterator[VimCompletion]:
    scr_width, _ = stack.state.screen
    display = stack.settings.display
    _, col = context.position
    truncate = clamp(1, scr_width - col - display.pum.x_margin, display.pum.x_max_len)
    dead_spaces = sum(
        display_width(s, tabsize=context.tabstop, linefeed=context.linefeed)
        for s in chain(display.pum.kind_context, display.pum.source_context)
    )

    max_width, w_adjust = _cum(stack.settings.weights, metrics=metrics)
    sortby = _sort_by(w_adjust)
    ranked = sorted(metrics, key=sortby)

    seen: MutableSet[str] = set()
    for metric in ranked:
        if metric.comp.primary_edit.new_text not in seen:
            seen.add(metric.comp.primary_edit.new_text)
            yield _cmp_to_vcmp(
                display.pum,
                context=context,
                dead_spaces=dead_spaces,
                truncate=truncate,
                max_width=max_width,
                cmp=metric.comp,
            )

