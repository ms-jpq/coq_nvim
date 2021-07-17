from collections import Counter
from typing import AbstractSet, Iterable, Iterator, MutableSequence
from unicodedata import east_asian_width

_UNICODE_WIDTH_LOOKUP = {
    "W": 2,  # CJK
    "N": 2,  # Non printable
}

_SPECIAL = {"\n", "\r", "\0"}


def display_width(text: str, tabsize: int) -> int:
    def cont() -> Iterator[int]:

        for char in text:
            if char == "\t":
                yield tabsize
            elif char in _SPECIAL:
                yield 2
            else:
                code = east_asian_width(char)
                yield _UNICODE_WIDTH_LOOKUP.get(code, 1)

    return sum(cont())


def lower(text: str) -> str:
    return text.casefold()


def is_word(char: str, unifying_chars: AbstractSet[str]) -> bool:
    return char in unifying_chars or char.isalnum()


def coalesce(chars: Iterable[str], unifying_chars: AbstractSet[str]) -> Iterator[str]:
    words: MutableSequence[str] = []
    syms: MutableSequence[str] = []

    def wit() -> Iterator[str]:
        if words:
            word = "".join(words)
            words.clear()
            yield word

    def sit() -> Iterator[str]:
        if syms:
            sym = "".join(syms)
            syms.clear()
            yield sym

    for char in chars:
        if is_word(char, unifying_chars=unifying_chars):
            words.append(char)
            yield from sit()
        elif not char.isspace():
            syms.append(char)
            yield from wit()
        else:
            yield from wit()
            yield from sit()

    yield from wit()
    yield from sit()


def similarity(lhs: str, rhs: str) -> float:
    l_c, r_c = Counter(lhs), Counter(rhs)
    dif = l_c - r_c if len(lhs) > len(rhs) else r_c - l_c
    bigger, smaller = max(len(lhs), len(rhs)), min(len(lhs), len(rhs))
    ratio = 1 - sum(dif.values()) / bigger
    adjust = smaller / bigger
    return ratio / adjust

