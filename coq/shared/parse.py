from typing import AbstractSet, Iterable, Iterator, MutableSequence
from unicodedata import normalize as _normalize


def lower(text: str) -> str:
    return text.casefold()


def normalize(text: str) -> str:
    return _normalize("NFC", text)


def is_word(char: str, unifying_chars: AbstractSet[str]) -> bool:
    return char in unifying_chars or char.isalnum()


def coalesce(chars: Iterable[str], unifying_chars: AbstractSet[str]) -> Iterator[str]:
    curr: MutableSequence[str] = []

    for char in chars:
        if is_word(char, unifying_chars=unifying_chars):
            curr.append(char)

        elif curr:
            word = "".join(curr)
            curr.clear()
            yield word

    if curr:
        word = "".join(curr)
        yield word

