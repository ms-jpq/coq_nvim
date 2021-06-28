from dataclasses import asdict
from locale import strxfrm
from typing import Any, Callable, Iterable, Iterator, MutableSet, Sequence, Tuple

from std2.ordinal import clamp

from ..shared.nvim.completions import VimCompletion
from ..shared.parse import display_width
from ..shared.runtime import Metric
from ..shared.settings import PumDisplay, Weights
from ..shared.types import Context, SnippetEdit
from .runtime import Stack
from .types import UserData

_ZERO = Weights(
    consecutive_matches=0,
    count_by_filetype=0,
    insertion_order=0,
    match_density=0,
    neighbours=0,
    num_matches=0,
    prefix_matches=0,
)


def _cum(adjustment: Weights, metrics: Iterable[Metric]) -> Tuple[int, Weights]:
    acc = asdict(_ZERO)
    max_width = 0
    for metric in metrics:
        max_width = max(max_width, metric.label_width + metric.kind_width)
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


def _cmp_to_vcmp(
    pum: PumDisplay,
    context: Context,
    kind_dead_width: int,
    truncate: int,
    max_width: int,
    metric: Metric,
) -> VimCompletion:
    (kl, kr), (sl, sr) = pum.kind_context, pum.source_context
    kind = f"{kl}{metric.comp.kind}{kr}" if metric.comp.kind else ""
    menu = f"{sl}{metric.comp.source}{sr}"

    label_width = metric.label_width
    kind_width = metric.kind_width + kind_dead_width
    tr = truncate - kind_width

    if label_width > tr:
        label_lhs = metric.comp.label[: tr - len(pum.ellipsis)] + pum.ellipsis
    else:
        max_truncated_to = min(max_width + kind_dead_width, tr)
        just = max_truncated_to - kind_width
        label_lhs = metric.comp.label.ljust(just)

    abbr = label_lhs + kind
    user_data = UserData(
        sort_by=metric.comp.sort_by,
        commit_uid=context.uid,
        primary_edit=metric.comp.primary_edit,
        secondary_edits=metric.comp.secondary_edits,
        doc=metric.comp.doc,
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

    kind_dead_width = sum(
        display_width(s, tabsize=context.tabstop, linefeed=context.linefeed)
        for s in display.pum.kind_context
    )
    truncate = clamp(1, scr_width - col - display.pum.x_margin, display.pum.x_max_len)

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
                kind_dead_width=kind_dead_width,
                truncate=truncate,
                max_width=max_width,
                metric=metric,
            )

