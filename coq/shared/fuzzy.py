from collections import Counter
from dataclasses import dataclass
from itertools import repeat
from typing import Iterator, MutableMapping


@dataclass(frozen=True)
class MatchMetrics:
    prefix_matches: int
    edit_distance: float


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


def dl_distance(lhs: str, rhs: str) -> int:
    """
    Modified from
    https://github.com/jamesturk/jellyfish/blob/main/LICENSE
    Dont sue me
    """

    len_l, len_r = len(lhs), len(rhs)
    max_d = len_l + len_r

    da: MutableMapping[str, int] = {}

    d = [*repeat([*repeat(0, times=len_r + 2)], times=len_l + 2)]
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


def metrics(cword: str, match: str) -> MatchMetrics:
    shorter = min(len(cword), len(match))
    if not shorter:
        return MatchMetrics(prefix_matches=0, edit_distance=0)
    else:

        def pre() -> Iterator[str]:
            for lhs, rhs in zip(cword, match):
                if lhs == rhs:
                    yield lhs
                else:
                    break

        pl = len(tuple(pre()))
        lhs, rhs = cword[pl:shorter], match[pl:shorter]
        dist = dl_distance(lhs, rhs)
        edit_dist = 1 - dist / shorter
        return MatchMetrics(prefix_matches=pl, edit_distance=edit_dist)

