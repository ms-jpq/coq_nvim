from typing import Dict, Iterable, Iterator, List, Set, Tuple

from .da import subsequences
from .types import Context


def normalize(text: str) -> str:
    return text.lower()


def is_word(char: str, unifying_chars: Set[str]) -> bool:
    return char in unifying_chars or char.isalnum()


def is_sym(char: str) -> bool:
    return not char.isalnum() and not char.isspace()


def coalesce(
    chars: Iterable[str], max_length: int, unifying_chars: Set[str]
) -> Iterator[str]:
    curr: List[str] = []
    for char in chars:
        if is_word(char, unifying_chars=unifying_chars):
            curr.append(char)
        elif curr:
            word = "".join(curr)
            curr.clear()
            wl = len(word)
            if wl <= max_length:
                yield word

    if curr:
        word = "".join(curr)
        wl = len(word)
        if wl >= max_length:
            yield word


def parse_common_affix(
    context: Context, match_normalized: str, use_line: bool
) -> Tuple[str, str]:
    before, after = (
        (context.line_before, context.line_after)
        if use_line
        else (context.alnums_before, context.alnums_after)
    )
    before_normalized, after_normalized = (
        (context.line_before_normalized, context.line_after_normalized,)
        if use_line
        else (context.alnums_before_normalized, context.alnums_after_normalized)
    )

    pre_it = zip(
        subsequences(before, reverse=True),
        subsequences(before_normalized, reverse=True),
        subsequences(match_normalized),
    )

    prefix = context.alnums_before
    idx = -1
    for i, (text, lhs, rhs) in enumerate(pre_it):
        if lhs == rhs:
            prefix = "".join(text)
            idx = i

    suffix = context.alnums_after
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
