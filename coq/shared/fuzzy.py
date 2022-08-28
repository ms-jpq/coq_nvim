from array import array
from collections import Counter
from dataclasses import dataclass
from itertools import repeat
from typing import Iterable, MutableMapping, MutableSequence, Tuple


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


def multi_set_ratio(lhs: str, rhs: str, look_ahead: int) -> float:
    """
    Test intersection size, adjust for length
    """

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


def quick_ratio(lhs: str, rhs: str, look_ahead: int) -> float:
    """
    Front end bias
    """

    shorter = min(len(lhs), len(rhs))
    if not shorter:
        return 1
    else:
        p_matches = _p_matches(lhs, rhs)
        l, r = lhs[p_matches:], rhs[p_matches:]

        l_ratio = p_matches / shorter
        r_ratio = multi_set_ratio(l, r, look_ahead=look_ahead) * (1 - l_ratio)
        return l_ratio + r_ratio * 0.5


_ARRAY_CACHE: MutableMapping[Tuple[int, int], MutableSequence[int]] = {}
_DA: MutableMapping[str, int] = {}


def dl_distance(lhs: str, rhs: str) -> int:
    """
    Modified from
    https://github.com/jamesturk/jellyfish/blob/main/LICENSE
    Dont sue me
    """

    len_l, len_r = len(lhs), len(rhs)
    row_size = len_r + 2
    max_d = len_l + len_r
    _DA.clear()

    if not (d := _ARRAY_CACHE.get((len_l, len_r))):
        d = array("I", repeat(0, row_size * (len_l + 2)))

    d[0] = max_d
    for i in range(0, len_l + 1):
        i1 = i + 1
        d[row_size * i1] = max_d
        d[row_size * i1 + 1] = i

    for j in range(0, len_r + 1):
        d[j + 1] = max_d
        d[row_size + j + 1] = j

    for i in range(1, len_l + 1):
        db = 0
        for j in range(1, len_r + 1):
            i1 = _DA.get(rhs[j - 1], 0)
            j1 = db

            if lhs[i - 1] == rhs[j - 1]:
                cost = 0
                db = j
            else:
                cost = 1

            d[row_size * (i + 1) + j + 1] = min(
                d[row_size * i + j] + cost,
                d[row_size * (i + 1) + j] + 1,
                d[row_size * i + j + 1] + 1,
                d[row_size * i1 + j1] + (i - i1 - 1) + 1 + (j - j1 - 1),
            )
        _DA[lhs[i - 1]] = i

    return d[row_size * (len_l + 1) + len_r + 1]


def metrics(lhs: str, rhs: str, look_ahead: int) -> MatchMetrics:
    """
    Front end bias
    """

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
