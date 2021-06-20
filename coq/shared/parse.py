from typing import AbstractSet, Iterable, Iterator, MutableSequence
from unicodedata import normalize as _normalize


def lower(text: str) -> str:
    return text.casefold()


def normalize(text: str) -> str:
    return _normalize("NFC", text)


def is_word(char: str, unifying_chars: AbstractSet[str]) -> bool:
    return char in unifying_chars or char.isalnum()


def coalesce(chars: Iterable[str], unifying_chars: AbstractSet[str]) -> Iterator[str]:
    words: MutableSequence[str] = []
    syms: MutableSequence[str] = []

    for char in chars:
        if is_word(char, unifying_chars=unifying_chars):
            words.append(char)
        elif not char.isspace():
            syms.append(char)
        else:
            if words:
                word = "".join(words)
                words.clear()
                yield word
            if syms:
                sym = "".join(syms)
                syms.clear()
                yield sym

    if words:
        yield "".join(words)

    if syms:
        yield "".join(syms)

