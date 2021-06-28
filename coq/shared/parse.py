from typing import AbstractSet, Iterable, Iterator, Literal, MutableSequence
from unicodedata import east_asian_width

_UNICODE_WIDTH_LOOKUP = {
    "W": 2,  # CJK
    "N": 2,  # Non printable
}


def display_width(
    text: str, tabsize: int, linefeed: Literal["\r\n", "\n", "\r"]
) -> int:
    def cont() -> Iterator[int]:

        for char in text:
            if char == "\t":
                yield tabsize
            elif char == linefeed:
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

