from concurrent.futures import FIRST_EXCEPTION, Future, wait
from itertools import islice
from locale import strxfrm
from pprint import pformat
from string import Template
from textwrap import dedent
from typing import Any, Callable, Iterable, Iterator, Sequence, Tuple, cast

from pynvim_pp.logging import log

from ..consts import DEBUG_METRICS
from ..registry import pool
from ..shared.settings import Options, Weights
from ..shared.timeit import timeit
from ..shared.types import Completion, Context, SnippetEdit

_ZERO = Weights(
    consecutive_matches=0,
    count_by_filetype=0,
    insertion_order=0,
    match_density=0,
    nearest_neighbour=0,
    num_matches=0,
    prefix_matches=0,
)


def _cum(adjustment: Weights, it: Iterable[_M]) -> Tuple[int, Weights]:
    acc = asdict(_ZERO)
    max_len = 0
    for cmp, weight in it:
        max_len = max(max_len, (len(cmp.label) + len(cmp.kind)))
        for key, val in asdict(weight).items():
            acc[key] += val
    for key, val in asdict(adjustment).items():
        acc[key] /= val

    return max_len, Weights(**acc)


def _sort_by(cum: Weights) -> Callable[[_M], Any]:
    adjustment = asdict(cum)

    def key_by(single: _M) -> Any:
        cmp, weight = single
        tot = sum(
            val / adjustment[key] if adjustment[key] else 0
            for key, val in asdict(weight).items()
        )
        return (
            -round(tot * 1000),
            -len(cmp.secondary_edits),
            -(cmp.doc is not None),
            -isinstance(cmp.primary_edit, SnippetEdit),
            -cmp.tie_breaker,
            strxfrm(cmp.sort_by or cmp.primary_edit.new_text),
        )

    return key_by


def _debug_log(
    key_by: Callable[[_M], Any],
    cum: Weights,
    ordered: Sequence[_M],
) -> None:
    def cont() -> Iterator[Any]:
        for cmp, weight in islice(ordered, 20):
            word = cmp.sort_by or cmp.primary_edit.new_text
            yield word, weight, key_by((cmp, weight))

    t = f"""
    {"#" * 20}
    $cum
    $rows
    {"#" * 20}
    """
    msg = Template(dedent(t)).substitute(cum=pformat(cum), rows=pformat(tuple(cont())))
    log.debug("%s", msg)


def annotate(
    options: Options,
    weights: Weights,
    context: Context,
    completions: Sequence[Completion],
) -> Tuple[int, Iterator[Completion]]:
    @timeit("RANK :: SQL")
    def c1() -> Sequence[SqlMetrics]:
        row, _ = context.position
        return db.metric(
            words,
            filetype=context.filetype,
            filename=context.filename,
            line_num=row,
        )

    @timeit("RANK :: MAN")
    def c2() -> Sequence[_MatchMetrics]:
        return tuple(_metrics(options, context=context, completions=completions))

    with timeit("RANK :: T2"):
        f1, f2 = pool.submit(c1), pool.submit(c2)
        wait((cast(Future, f1), cast(Future, f2)), return_when=FIRST_EXCEPTION)

    metrics = zip(completions, f1.result(), f2.result())
    individual = tuple(_weights(metrics))
    max_len, cum = _cum(weights, it=individual)
    key_by = _sort_by(cum)
    ordered = sorted(individual, key=key_by)
    if DEBUG_METRICS:
        _debug_log(key_by, cum=cum, ordered=ordered)
    return max_len, (c for c, _ in ordered)

