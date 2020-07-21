from typing import Tuple

from .da import subsequences


def parse_common_affix(
    before: str,
    before_normalized: str,
    after: str,
    after_normalized: str,
    match_normalized: str,
) -> Tuple[str, str]:
    pre_it = zip(
        subsequences(before, reverse=True),
        subsequences(before_normalized, reverse=True),
        subsequences(match_normalized),
    )
    post_it = zip(
        subsequences(after),
        subsequences(after_normalized),
        subsequences(match_normalized, reverse=True),
    )

    prefix = ""
    for text, lhs, rhs in pre_it:
        if lhs == rhs:
            prefix = "".join(text)
            break

    suffix = ""
    for text, lhs, rhs in post_it:
        if lhs == rhs:
            suffix = "".join(text)
            break

    return prefix, suffix
