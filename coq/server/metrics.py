from concurrent.futures import FIRST_EXCEPTION, Future, wait
from dataclasses import asdict, dataclass
from difflib import SequenceMatcher
from itertools import islice
from locale import strxfrm
from math import inf
from pprint import pformat
from string import Template
from textwrap import dedent
from typing import (
    Any,
    Callable,
    Iterable,
    Iterator,
    MutableSequence,
    Sequence,
    Tuple,
    cast,
)

from pynvim_pp.logging import log

from ..consts import DEBUG_METRICS
from ..registry import pool
from ..shared.parse import is_word, lower
from ..shared.settings import Options, Weights
from ..shared.timeit import timeit
from ..shared.types import Completion, Context, SnippetEdit
from .model.buffers.database import BDB, SqlMetrics

_M = Tuple[Completion, Weights]


@dataclass(frozen=True)
class _MatchMetrics:
    prefix_matches: int
    match_density: float
    consecutive_matches: int
    num_matches: int


_ZERO = Weights(
    consecutive_matches=0,
    count_by_filetype=0,
    insertion_order=0,
    match_density=0,
    nearest_neighbour=0,
    num_matches=0,
    prefix_matches=0,
)


def _isjunk(s: str) -> bool:
    return s.isspace()


def count(cword: str, match: str) -> _MatchMetrics:
    m = SequenceMatcher(a=cword, b=match, autojunk=True, isjunk=_isjunk)
    matches: MutableSequence[int] = []
    prefix_matches = 0
    num_matches = 0
    consecutive_matches = 0

    for ai, bi, size in m.get_matching_blocks():
        num_matches += size
        if ai == bi == 0:
            prefix_matches = size
        for i in range(bi, bi + size):
            matches.append(i)

    pm_idx = inf
    for i in matches:
        if pm_idx == i - 1:
            consecutive_matches += 1
        pm_idx = i

    match_density = num_matches / len(match) if match else 0
    metric = _MatchMetrics(
        prefix_matches=prefix_matches,
        consecutive_matches=consecutive_matches,
        match_density=match_density,
        num_matches=num_matches,
    )
    return metric


def _metrics(
    options: Options, context: Context, completions: Iterable[Completion]
) -> Iterator[_MatchMetrics]:
    w_before = lower(context.words_before)
    s_before = lower(context.syms_before)

    for completion in completions:
        match = lower(completion.primary_edit.new_text)
        cword = (
            w_before
            if is_word(match[:1], unifying_chars=options.unifying_chars)
            else s_before
        )
        yield count(cword, match=match)


def _weights(
    metrics: Iterable[Tuple[Completion, SqlMetrics, _MatchMetrics]]
) -> Iterator[_M]:
    for cmp, sql, match in metrics:
        weight = Weights(
            consecutive_matches=match.consecutive_matches,
            count_by_filetype=sql["ft_count"],
            insertion_order=sql["insertion_order"],
            match_density=match.match_density,
            nearest_neighbour=sql["line_diff"],
            num_matches=match.num_matches,
            prefix_matches=match.prefix_matches,
        )
        yield cmp, weight


def _cum(adjustment: Weights, weights: Iterable[Weights]) -> Weights:
    acc = asdict(_ZERO)
    for weight in weights:
        for key, val in asdict(weight).items():
            acc[key] += val
    for key, val in asdict(adjustment).items():
        acc[key] /= val
    return Weights(**acc)


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


def rank(
    options: Options,
    weights: Weights,
    db: BDB,
    context: Context,
    completions: Sequence[Completion],
) -> Iterator[Completion]:
    def c1() -> Sequence[SqlMetrics]:
        with timeit("RANK :: SQL"):
            words = tuple(
                comp.sort_by or comp.primary_edit.new_text for comp in completions
            )
            row, _ = context.position
            return db.metric(
                words,
                filetype=context.filetype,
                filename=context.filename,
                line_num=row,
            )

    def c2() -> Sequence[_MatchMetrics]:
        with timeit("RANK :: MAN"):
            return tuple(_metrics(options, context=context, completions=completions))

    with timeit("RANK :: T2"):
        f1, f2 = pool.submit(c1), pool.submit(c2)
        wait((cast(Future, f1), cast(Future, f2)), return_when=FIRST_EXCEPTION)
        metrics = zip(completions, f1.result(), f2.result())

    with timeit("RANK :: SORT"):
        individual = tuple(_weights(metrics))
        cum = _cum(weights, weights=(w for _, w in individual))
        key_by = _sort_by(cum)
        ordered = sorted(individual, key=key_by)
        if DEBUG_METRICS:
            _debug_log(key_by, cum=cum, ordered=ordered)
        return (c for c, _ in ordered)

