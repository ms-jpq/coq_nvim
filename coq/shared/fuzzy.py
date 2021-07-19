from collections import Counter


def quick_ratio(lhs: str, rhs: str) -> float:
    bigger, smaller = max(len(lhs), len(rhs)), min(len(lhs), len(rhs))
    if not bigger or not smaller:
        return 1
    else:
        l_c, r_c = Counter(lhs), Counter(rhs)
        dif = l_c - r_c if len(lhs) > len(rhs) else r_c - l_c
        ratio = 1 - sum(dif.values()) / bigger
        adjust = smaller / bigger
        return ratio / adjust

