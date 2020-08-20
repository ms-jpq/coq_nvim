from typing import List, Set, Tuple

from ..shared.da import subsequences
from ..shared.parse import is_sym, is_word, normalize


def gen_lhs_rhs(
    line_before: str, line_after: str, unifying_chars: Set[str]
) -> Tuple[str, str, str, str]:
    lit = reversed(line_before)
    l_alnums: List[str] = []
    l_syms: List[str] = []
    for c in lit:
        if is_word(c, unifying_chars=unifying_chars):
            l_alnums.append(c)
        else:
            if is_sym(c):
                l_syms.append(c)
            break

    for c in lit:
        if is_sym(c):
            l_syms.append(c)
        else:
            break

    rit = iter(line_after)
    r_alnums: List[str] = []
    r_syms: List[str] = []
    for c in rit:
        if is_word(c, unifying_chars=unifying_chars):
            r_alnums.append(c)
        else:
            if is_sym(c):
                r_syms.append(c)
            break

    for c in rit:
        if is_sym(c):
            r_syms.append(c)
        else:
            break

    alnums_before = "".join(reversed(l_alnums))
    alnums_after = "".join(r_alnums)

    syms_before = "".join(reversed(l_syms))
    syms_after = "".join(r_syms)
    return syms_before, alnums_before, alnums_after, syms_after


def parse_common_affix(
    before: str, after: str, match_normalized: str, unifying_chars: Set[str]
) -> Tuple[str, str]:
    syms_before, alnums_before, alnums_after, syms_after = gen_lhs_rhs(
        before, after, unifying_chars=unifying_chars
    )
    before_normalized, after_normalized = normalize(before), normalize(after)

    pre_it = zip(
        subsequences(before, reverse=True),
        subsequences(before_normalized, reverse=True),
        subsequences(match_normalized),
    )

    prefix = alnums_before
    idx = -1
    for i, (text, lhs, rhs) in enumerate(pre_it):
        if lhs == rhs:
            prefix = "".join(text)
            idx = i

    suffix = alnums_after
    rest = match_normalized[idx + 1 :]
    post_it = zip(
        subsequences(after),
        subsequences(after_normalized),
        subsequences(rest, reverse=True),
    )
    for text, lhs, rhs in post_it:
        if lhs == rhs:
            suffix = "".join(text)

    return prefix, suffix
