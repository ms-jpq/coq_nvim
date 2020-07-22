from typing import Callable, Iterator, List, Sequence, Set, Tuple

from .da import subsequences


def normalize(text: str) -> str:
    return text.lower()


def count_matches(cword: str, word: str) -> int:
    idx = 0
    count = 0
    for char in cword:
        m_idx = word.find(char, idx)
        if m_idx != -1:
            count += 1
            idx = m_idx + 1

    return count


def coalesce(cword: str, min_length: int) -> Callable[[Sequence[str]], Iterator[str]]:
    acc: Set[str] = {cword}

    def parse(chars: Sequence[str]) -> Iterator[str]:
        curr: List[str] = []
        for char in chars:
            if char.isalnum():
                curr.append(char)
            elif curr:
                word = "".join(curr)
                normalized = normalize(word)
                if (
                    normalized not in acc
                    and count_matches(cword, word=normalized) >= min_length
                ):
                    acc.add(word)
                    yield word
                curr.clear()

        if curr:
            word = "".join(curr)
            if word not in acc:
                yield word

    return parse


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

    suffix = ""
    for text, lhs, rhs in post_it:
        if lhs == rhs:
            suffix = "".join(text)

    return prefix, suffix
