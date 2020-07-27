from typing import Dict, Iterable, Iterator, List, Tuple

from .da import subsequences
from .types import Context


def normalize(text: str) -> str:
    return text.lower()


def is_sym(char: str) -> bool:
    return not char.isalnum() and not char.isspace()


def count_matches(cword: str, word: str, nword: str) -> int:
    idx = 0
    count = 0
    for char in cword:
        m_idx = (word if char.isupper() else nword).find(char, idx)
        if m_idx != -1:
            count += 1
            idx = m_idx + 1

    return count


def find_matches(
    cword: str, ncword: str, min_match: int, words: Dict[str, str]
) -> Iterator[str]:
    for word, nword in words.items():
        matches = count_matches(cword, word=word, nword=nword)
        if matches >= min_match and nword not in ncword:
            yield word


def coalesce(chars: Iterable[str], max_length: int) -> Iterator[str]:
    curr: List[str] = []
    for char in chars:
        if char.isalnum():
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


def parse_common_affix(context: Context, match_normalized: str,) -> Tuple[str, str]:
    before, after = context.line_before, context.line_after
    before_normalized, after_normalized = (
        context.line_before_normalized,
        context.line_after_normalized,
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
