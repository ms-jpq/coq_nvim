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

    def w_it() -> Iterator[str]:
        if words:
            word = "".join(words)
            words.clear()
            yield word

    def s_it() -> Iterator[str]:
        if syms:
            sym = "".join(syms)
            syms.clear()
            yield sym

    for char in chars:
        if is_word(char, unifying_chars=unifying_chars):
            words.append(char)
            yield from s_it()
        elif not char.isspace():
            syms.append(char)
            yield from w_it()
        else:
            yield from w_it()
            yield from s_it()

    yield from w_it()
    yield from s_it()
