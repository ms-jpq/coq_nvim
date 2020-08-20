from typing import Tuple

from ..shared.da import subsequences
from ..shared.parse import normalize


def parse_common_affix(before, after, match_normalized: str) -> Tuple[str, str]:
    before_normalized, after_normalized = normalize(before), normalize(after)

    pre_it = zip(
        subsequences(before, reverse=True),
        subsequences(before_normalized, reverse=True),
        subsequences(match_normalized),
    )

    prefix = before
    idx = -1
    for i, (text, lhs, rhs) in enumerate(pre_it):
        if lhs == rhs:
            prefix = "".join(text)
            idx = i

    suffix = after
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
