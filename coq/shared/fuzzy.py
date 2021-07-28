from collections import Counter
from dataclasses import dataclass
from typing import Iterable, MutableMapping


@dataclass(frozen=True)
class MatchMetrics:
    prefix_matches: int
    edit_distance: float


def _p_matches(lhs: Iterable[str], rhs: Iterable[str]) -> int:
    p_matches = 0
    for l, r in zip(lhs, rhs):
        if l == r:
            p_matches += 1
        else:
            break
    return p_matches


def multi_set_ratio(lhs: str, rhs: str) -> float:
    shorter = min(len(lhs), len(rhs))
    if not shorter:
        return 0
    else:
        longer = max(len(lhs), len(rhs))
        l_c, r_c = Counter(lhs), Counter(rhs)
        dif = l_c - r_c if len(lhs) > len(rhs) else r_c - l_c
        ratio = 1 - sum(dif.values()) / longer
        adjust = shorter / longer
        return ratio / adjust


def quick_ratio(lhs: str, rhs: str, look_ahead: int) -> float:
    shorter = min(len(lhs), len(rhs))
    if not shorter:
        return 1
    else:
        p_matches = _p_matches(lhs, rhs)
        cutoff = min(max(len(lhs), len(rhs)), shorter + look_ahead)
        l, r = lhs[p_matches:cutoff], rhs[p_matches:cutoff]
        l_ratio = p_matches / shorter
        r_ratio = multi_set_ratio(l, r)
        return l_ratio + r_ratio


def dl_distance(lhs: str, rhs: str) -> int:
    """
    Modified from
    https://github.com/jamesturk/jellyfish/blob/main/LICENSE
    Dont sue me
    """

    len_l, len_r = len(lhs), len(rhs)
    max_d = len_l + len_r

    da: MutableMapping[str, int] = {}

    d = [[0] * (len_r + 2) for _ in range(len_l + 2)]

    d[0][0] = max_d
    for i in range(0, len_l + 1):
        d[i + 1][0] = max_d
        d[i + 1][1] = i
    for j in range(0, len_r + 1):
        d[0][j + 1] = max_d
        d[1][j + 1] = j

    for i in range(1, len_l + 1):
        db = 0
        for j in range(1, len_r + 1):
            i1 = da.get(rhs[j - 1], 0)
            j1 = db

            if lhs[i - 1] == rhs[j - 1]:
                cost = 0
                db = j
            else:
                cost = 1

            d[i + 1][j + 1] = min(
                d[i][j] + cost,
                d[i + 1][j] + 1,
                d[i][j + 1] + 1,
                d[i1][j1] + (i - i1 - 1) + 1 + (j - j1 - 1),
            )
        da[lhs[i - 1]] = i

    return d[len_l + 1][len_r + 1]


def metrics(lhs: str, rhs: str, look_ahead: int) -> MatchMetrics:
    shorter = min(len(lhs), len(rhs))
    if not shorter:
        return MatchMetrics(prefix_matches=0, edit_distance=0)
    else:
        p_matches = _p_matches(lhs, rhs)
        cutoff = min(max(len(lhs), len(rhs)), shorter + look_ahead)
        more = cutoff - shorter
        l, r = lhs[p_matches:cutoff], rhs[p_matches:cutoff]

        dist = dl_distance(l, r)
        edit_dist = 1 - (dist - more) / shorter
        return MatchMetrics(prefix_matches=p_matches, edit_distance=edit_dist)

