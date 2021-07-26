from dataclasses import asdict
from locale import strxfrm
from typing import Any, Callable, Iterable, Iterator, MutableSet, Sequence, Tuple

from std2.ordinal import clamp

from ..shared.parse import display_width
from ..shared.runtime import Metric
from ..shared.settings import PumDisplay, Weights
from ..shared.types import Context
from .nvim.completions import UserData, VimCompletion
from .rt_types import Stack
from .state import state


def _cum(adjustment: Weights, metrics: Iterable[Metric]) -> Tuple[int, Weights]:
    zero = Weights(
        prefix_matches=0,
        edit_distance=0,
        insertion_order=0,
        neighbours=0,
    )
    acc = asdict(zero)
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
        key = (
            -round(tot * 1000),
            -len(metric.comp.secondary_edits),
            -(metric.comp.kind != ""),
            -metric.comp.tie_breaker,
            -(metric.comp.doc is not None),
            -metric.comp.sort_by[:1].isalnum(),
            strxfrm(metric.comp.sort_by),
        )
        return key

    return key_by


def _cmp_to_vcmp(
    pum: PumDisplay,
    context: Context,
    kind_dead_width: int,
    ellipsis_width: int,
    truncate: int,
    max_width: int,
    metric: Metric,
) -> VimCompletion:
    (kl, kr), (sl, sr) = pum.kind_context, pum.source_context
    kind = f"{kl}{metric.comp.kind}{kr}" if metric.comp.kind else ""

    label_width = metric.label_width
    kind_width = metric.kind_width + kind_dead_width
    tr = truncate - kind_width

    if (kind_width + ellipsis_width + pum.x_min_len) > truncate:
        truncated = metric.comp.label[: max(1, truncate - ellipsis_width)]
        label_lhs = (
            truncated + pum.ellipsis if truncated != metric.comp.label else truncated
        )
        abbr = label_lhs
    elif label_width > tr:
        label_lhs = metric.comp.label[: tr - ellipsis_width] + pum.ellipsis
        abbr = label_lhs + kind
    else:
        truncated_to = min(max_width + kind_dead_width, truncate) - kind_width
        label_lhs = metric.comp.label.ljust(truncated_to)
        abbr = label_lhs + kind

    menu = f"{sl}{metric.comp.source}{sr}"

    user_data = UserData(
        uid=metric.comp.uid,
        instance=metric.istance,
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

    kind_dead_width = sum(
        display_width(s, tabsize=context.tabstop) for s in display.pum.kind_context
    )
    ellipsis_width = display_width(display.pum.ellipsis, tabsize=context.tabstop)
    truncate = clamp(1, scr_width - context.scr_col, display.pum.x_max_len)

    max_width, w_adjust = _cum(stack.settings.weights, metrics=metrics)
    sortby = _sort_by(w_adjust)
    ranked = sorted(metrics, key=sortby)

    seen: MutableSet[str] = set()
    for metric in ranked:
        if not context.manual and len(seen) > stack.settings.match.max_results:
            break
        elif metric.comp.primary_edit.new_text not in seen:
            seen.add(metric.comp.primary_edit.new_text)
            yield _cmp_to_vcmp(
                display.pum,
                context=context,
                ellipsis_width=ellipsis_width,
                kind_dead_width=kind_dead_width,
                truncate=truncate,
                max_width=max_width,
                metric=metric,
            )

