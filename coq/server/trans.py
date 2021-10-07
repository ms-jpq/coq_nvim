from dataclasses import asdict
from itertools import chain
from locale import strxfrm
from typing import Any, Callable, Iterable, Iterator, MutableSet, Sequence, Tuple

from pynvim_pp.lib import display_width
from std2 import clamp

from ..shared.parse import lower
from ..shared.runtime import Metric
from ..shared.settings import PumDisplay, Weights
from ..shared.types import Context, SnippetEdit
from .completions import VimCompletion
from .rt_types import Stack
from .state import state


def _cum(adjustment: Weights, metrics: Iterable[Metric]) -> Weights:
    zero = Weights(
        prefix_matches=0,
        edit_distance=0,
        recency=0,
        proximity=0,
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


def _sort_by(is_lower: bool, adjustment: Weights) -> Callable[[Metric], Any]:
    adjust = asdict(adjustment)

    def key_by(metric: Metric) -> Any:
        tot = sum(
            val / adjust[key] if adjust[key] else 0
            for key, val in asdict(metric.weight).items()
        )
        key = (
            -(metric.comp.preselect),
            -round(tot * metric.weight_adjust * 1000),
            -len(metric.comp.secondary_edits),
            -(metric.comp.kind != ""),
            -(metric.comp.doc is not None),
            -metric.comp.sort_by[:1].isalnum(),
            strxfrm(
                metric.comp.sort_by.swapcase() if is_lower else metric.comp.sort_by
            ),
        )
        return key

    return key_by


def _prune(
    stack: Stack, context: Context, ranked: Iterable[Metric]
) -> Iterator[Metric]:
    seen: MutableSet[str] = set()
    for metric in ranked:
        p_edit = metric.comp.primary_edit
        if not context.manual and len(seen) > stack.settings.match.max_results:
            break
        elif p_edit.new_text not in seen:
            if not isinstance(p_edit, SnippetEdit):
                seen.add(p_edit.new_text)
            yield metric


def _max_width(metrics: Sequence[Metric]) -> int:
    max_width = max(
        chain((0,), (metric.label_width + metric.kind_width for metric in metrics))
    )
    return max_width


def _cmp_to_vcmp(
    pum: PumDisplay,
    label_width: int,
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

    if (kind_width + ellipsis_width + pum.x_truncate_len) > truncate:
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
        label_lhs = metric.comp.label + (truncated_to - label_width) * " "
        abbr = label_lhs + kind

    menu = f"{sl}{metric.comp.source}{sr}"

    vcmp = VimCompletion(abbr=abbr, menu=menu, user_data=metric.comp.uid)
    return vcmp


def trans(
    stack: Stack, context: Context, metrics: Sequence[Metric]
) -> Iterator[Tuple[Metric, VimCompletion]]:
    s = state()
    scr_width, _ = s.screen

    display = stack.settings.display
    is_lower = lower(context.words_before) == context.words_before

    kind_dead_width = sum(
        display_width(s, tabsize=context.tabstop) for s in display.pum.kind_context
    )
    ellipsis_width = display_width(display.pum.ellipsis, tabsize=context.tabstop)
    truncate = clamp(context.pumwidth, scr_width - context.scr_col, display.pum.x_max_len)

    w_adjust = _cum(stack.settings.weights, metrics=metrics)
    sortby = _sort_by(is_lower, adjustment=w_adjust)
    ranked = sorted(metrics, key=sortby)
    pruned = tuple(_prune(stack, context=context, ranked=ranked))
    max_width = _max_width(pruned)
    for metric in pruned:
        yield metric, _cmp_to_vcmp(
            display.pum,
            label_width=metric.label_width,
            ellipsis_width=ellipsis_width,
            kind_dead_width=kind_dead_width,
            truncate=truncate,
            max_width=max_width,
            metric=metric,
        )
