from dataclasses import asdict
from itertools import chain
from locale import strxfrm
from typing import Any, Callable, Iterable, Iterator, MutableSet, Sequence

from std2.ordinal import clamp

from ..shared.parse import display_width
from ..shared.runtime import Metric
from ..shared.settings import PumDisplay, Weights
from ..shared.types import Context
from .nvim.completions import UserData, VimCompletion
from .rt_types import Stack
from .state import state


def _cum(adjustment: Weights, metrics: Iterable[Metric]) -> Weights:
    zero = Weights(
        consecutive_matches=0,
        insertion_order=0,
        neighbours=0,
        num_matches=0,
        prefix_matches=0,
    )
    acc = asdict(zero)
    for metric in metrics:
        for key, val in asdict(metric.weight).items():
            acc[key] += val
    for key, val in asdict(adjustment).items():
        if val:
            acc[key] /= val
        else:
            acc[key] = 0
    return Weights(**acc)


def _sort_by(adjustment: Weights) -> Callable[[Metric], Any]:
    adjust = asdict(adjustment)

    def key_by(metric: Metric) -> Any:
        tot = sum(
            val / adjust[key] if adjust[key] else 0
            for key, val in asdict(metric.weight).items()
        )
        sort_by = metric.comp.sort_by or metric.comp.primary_edit.new_text
        return (
            -round(tot * 1000),
            -len(metric.comp.secondary_edits),
            -metric.comp.tie_breaker,
            -(metric.comp.doc is not None),
            -sort_by[:1].isalnum(),
            strxfrm(sort_by),
        )

    return key_by


def _cmp_to_vcmp(
    pum: PumDisplay,
    context: Context,
    ellipsis_width: int,
    truncate_label: int,
    truncate_kind: int,
    metric: Metric,
) -> VimCompletion:
    (kl, kr), (sl, sr) = pum.kind_context, pum.source_context

    if metric.label_width > truncate_label:
        abbr = metric.comp.label[2 : truncate_label - ellipsis_width - 2] + pum.ellipsis
    else:
        abbr = metric.comp.label
    if metric.kind_width > truncate_kind:
        src = metric.comp.source[2 : truncate_kind - ellipsis_width - 2] + pum.ellipsis
    else:
        src = metric.comp.kind

    kind = f"{kl}{metric.comp.kind}{kr}" if metric.comp.kind else None
    menu = f"{sl}{src}{sr}"
    user_data = UserData(
        change_uid=context.change_id,
        sort_by=metric.comp.sort_by,
        primary_edit=metric.comp.primary_edit,
        secondary_edits=metric.comp.secondary_edits,
        doc=metric.comp.doc,
        extern=metric.comp.extern,
    )
    vcmp = VimCompletion(
        word="",
        empty=1,
        dup=1,
        equal=1,
        abbr=abbr,
        kind=kind,
        menu=menu,
        user_data=user_data,
    )
    return vcmp


def trans(
    stack: Stack, context: Context, metrics: Sequence[Metric]
) -> Iterator[VimCompletion]:
    s = state()
    scr_width, _ = s.screen

    display = stack.settings.display
    _, col = context.position

    decoration_width = sum(
        display_width(s, tabsize=context.tabstop, linefeed=context.linefeed)
        for s in chain(display.pum.kind_context, display.pum.source_context)
    )
    ellipsis_width = display_width(
        display.pum.ellipsis, tabsize=context.tabstop, linefeed=context.linefeed
    )
    truncate = clamp(
        1,
        scr_width - col - display.pum.x_margin - decoration_width,
        display.pum.x_max_len - decoration_width,
    )
    truncate_label = round(truncate * 0.7)
    truncate_kind = truncate - truncate_label

    w_adjust = _cum(stack.settings.weights, metrics=metrics)
    sortby = _sort_by(w_adjust)
    ranked = sorted(metrics, key=sortby)

    seen: MutableSet[str] = set()
    for metric in ranked:
        if metric.comp.primary_edit.new_text not in seen:
            seen.add(metric.comp.primary_edit.new_text)
            yield _cmp_to_vcmp(
                display.pum,
                context=context,
                ellipsis_width=ellipsis_width,
                truncate_label=truncate_label,
                truncate_kind=truncate_kind,
                metric=metric,
            )

