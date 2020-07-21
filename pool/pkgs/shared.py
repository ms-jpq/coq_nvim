from typing import Tuple

from .da import subsequences


def parse_common_affix(before: str, after: str, match: str) -> Tuple[str, str]:
    pre_it = zip(subsequences(before, reverse=True), subsequences(match))
    post_it = zip(subsequences(after), subsequences(match, reverse=True))

    prefix = ""
    for lhs, rhs in pre_it:
        if lhs == rhs:
            prefix = "".join(lhs)
            break

    suffix = ""
    for lhs, rhs in post_it:
        if lhs == rhs:
            suffix = "".join(lhs)
            break

    return prefix, suffix
