from collections import Counter
from dataclasses import dataclass
from difflib import SequenceMatcher
from math import inf
from typing import MutableSequence


@dataclass(frozen=True)
class MatchMetrics:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int


_LOOK_AHEAD = 3


def quick_ratio(lhs: str, rhs: str, look_ahead: int = _LOOK_AHEAD) -> float:
    shorter = min(len(lhs), len(rhs))
    if not shorter:
        return 1
    else:
        l, r = lhs[: shorter + look_ahead], rhs[: shorter + look_ahead]
        longer = max(len(l), len(r))
        l_c, r_c = Counter(l), Counter(r)
        dif = l_c - r_c if len(l) > len(r) else r_c - l_c
        ratio = 1 - sum(dif.values()) / longer
        adjust = shorter / longer
        return ratio / adjust


def _isjunk(s: str) -> bool:
    return s.isspace()


def count(cword: str, match: str) -> MatchMetrics:
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

    metric = MatchMetrics(
        prefix_matches=prefix_matches,
        consecutive_matches=consecutive_matches,
        num_matches=num_matches,
    )

    return metric

