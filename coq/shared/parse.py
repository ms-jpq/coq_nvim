from typing import AbstractSet, Iterable, Iterator, MutableSequence

from pynvim_pp.text_object import is_word


def lower(text: str) -> str:
    return text.casefold()


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
