from typing import Callable, Iterator, List, Sequence, Set, Tuple

from .da import subsequences
from .fc_types import Context


def normalize(text: str) -> str:
    return text.lower()


def count_matches(cword: str, word: str, nword: str) -> int:
    idx = 0
    count = 0
    for char in cword:
        m_idx = (word if char.isupper() else nword).find(char, idx)
        if m_idx != -1:
            count += 1
            idx = m_idx + 1

    return count


def coalesce(
    n_cword: str, min_length: int, max_length: int
) -> Callable[[Sequence[str]], Iterator[str]]:
    acc: Set[str] = {n_cword}

    def parse(chars: Sequence[str]) -> Iterator[str]:
        curr: List[str] = []
        for char in chars:
            if char.isalnum():
                curr.append(char)
            elif curr:
                word = "".join(curr)
                normalized = normalize(word)
                matches = count_matches(n_cword, word=word, nword=normalized)
                if (
                    normalized not in acc
                    and matches >= min_length
                    and matches <= max_length
                    and normalized not in n_cword
                ):
                    acc.add(normalized)
                    yield word
                curr.clear()

        if curr:
            word = "".join(curr)
            if word not in acc:
                yield word

    return parse


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

    prefix = ""
    idx = -1
    for i, (text, lhs, rhs) in enumerate(pre_it):
        if lhs == rhs:
            prefix = "".join(text)
            idx = i

    suffix = ""
    rest = match_normalized[idx + 1 :]
    post_it = zip(
        subsequences(after),
        subsequences(after_normalized),
        subsequences(rest, reverse=True),
    )
    for text, lhs, rhs in post_it:
        if lhs == rhs:
            suffix = "".join(text)

    if not prefix and not suffix:
        return context.alnums_before, context.alnums_after
    else:
        return prefix, suffix
