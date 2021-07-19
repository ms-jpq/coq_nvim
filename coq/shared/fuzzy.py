from collections import Counter
from dataclasses import dataclass
from difflib import SequenceMatcher
from itertools import repeat
from math import inf
from typing import MutableMapping, MutableSequence


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
        cutoff = shorter + look_ahead
        l, r = lhs[:cutoff], rhs[:cutoff]
        longer = max(len(l), len(r))
        l_c, r_c = Counter(l), Counter(r)
        dif = l_c - r_c if len(l) > len(r) else r_c - l_c
        ratio = 1 - sum(dif.values()) / longer
        adjust = shorter / longer
        return ratio / adjust


def osa_distance(lhs: str, rhs: str) -> int:
    len_l = len(lhs)
    len_r = len(rhs)
    inf = len_l + len_r

    acc: MutableMapping[str, int] = {}
    score = [*repeat([*repeat(0, times=len_r + 2)], times=len_l + 2)]

    score[0][0] = inf
    for i in range(0, len_l + 1):
        score[i + 1][0] = inf
        score[i + 1][1] = i
    for i in range(0, len_r + 1):
        score[0][i + 1] = inf
        score[1][i + 1] = i

    for i in range(1, len_l + 1):
        db = 0
        for j in range(1, len_r + 1):
            i1 = acc.get(rhs[j - 1], 0)
            j1 = db

            cost = 1
            if lhs[i - 1] == rhs[j - 1]:
                cost = 0
                db = j

            score[i + 1][j + 1] = min(
                score[i][j] + cost,
                score[i + 1][j] + 1,
                score[i][j + 1] + 1,
                score[i1][j1] + (i - i1 - 1) + 1 + (j - j1 - 1),
            )
        acc[lhs[i - 1]] = i

    return score[len_l + 1][len_r + 1]


def metrics(cword: str, match: str) -> MatchMetrics:
    m = SequenceMatcher(a=cword, b=match, autojunk=False)
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

