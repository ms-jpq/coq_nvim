from typing import AbstractSet, Iterable, Iterator, MutableSequence


def lower(text: str) -> str:
    return text.casefold()


def is_word(char: str, unifying_chars: AbstractSet[str]) -> bool:
    return char in unifying_chars or char.isalnum()


def is_sym(char: str, unifying_chars: AbstractSet[str]) -> bool:
    return not char.isspace() and not is_word(char, unifying_chars=unifying_chars)


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
