from dataclasses import dataclass
from difflib import SequenceMatcher
from math import inf
from typing import Iterable, Iterator, Mapping, MutableSequence, Sequence

from ..shared.parse import display_width, is_word, lower
from ..shared.runtime import Metric, PReviewer
from ..shared.settings import Options, Weights
from ..shared.types import Completion, Context
from .databases.insertions.database import IDB, SqlMetrics


@dataclass(frozen=True)
class _MatchMetrics:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    neighbours: int


def _isjunk(s: str) -> bool:
    return s.isspace()


def count(neighbours: Mapping[str, int], cword: str, match: str) -> _MatchMetrics:
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

    metric = _MatchMetrics(
        prefix_matches=prefix_matches,
        consecutive_matches=consecutive_matches,
        num_matches=num_matches,
        neighbours=neighbours.get(match, 0),
    )

    return metric


def _metrics(
    options: Options,
    context: Context,
    neighbours: Mapping[str, int],
    completions: Iterable[Completion],
) -> Iterator[_MatchMetrics]:
    w_before = lower(context.words_before)
    s_before = lower(context.syms_before)

    for completion in completions:
        cword = (
            w_before
            if is_word(completion.sort_by[:1], unifying_chars=options.unifying_chars)
            else s_before
        )
        yield count(neighbours, cword=cword, match=completion.sort_by)


def _join(
    context: Context, cmp: Completion, mm: _MatchMetrics, sqm: SqlMetrics
) -> Metric:
    weight = Weights(
        consecutive_matches=mm.consecutive_matches,
        insertion_order=sqm["insert_order"],
        neighbours=mm.neighbours,
        num_matches=mm.num_matches,
        prefix_matches=mm.prefix_matches,
    )

    label_width = display_width(
        cmp.label, tabsize=context.tabstop, linefeed=context.linefeed
    )
    kind_width = display_width(
        cmp.kind, tabsize=context.tabstop, linefeed=context.linefeed
    )
    metric = Metric(
        comp=cmp,
        weight=weight,
        label_width=label_width,
        kind_width=kind_width,
    )
    return metric


class Reviewer(PReviewer):
    def __init__(self, options: Options, db: IDB) -> None:
        self._options, self._db = options, db

    def rate(
        self,
        context: Context,
        neighbours: Mapping[str, int],
        completions: Sequence[Completion],
    ) -> Sequence[Metric]:
        words = tuple(comp.sort_by for comp in completions)
        mmm = _metrics(
            self._options,
            neighbours=neighbours,
            context=context,
            completions=completions,
        )
        dbm = self._db.metric(words)
        metrics = tuple(
            _join(context, cmp, mm, sqm) for cmp, mm, sqm in zip(completions, mmm, dbm)
        )
        return metrics

