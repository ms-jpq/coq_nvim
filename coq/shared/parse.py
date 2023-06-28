from itertools import islice
from random import choice
from typing import AbstractSet, Iterator, MutableSequence, Optional, Sequence

from pynvim_pp.text_object import is_word


def lower(text: str) -> str:
    return text.casefold()


def coalesce(
    unifying_chars: AbstractSet[str],
    include_syms: bool,
    backwards: Optional[bool],
    chars: Sequence[str],
) -> Iterator[str]:
    backwards = choice((True, False)) if backwards is None else backwards

    words: MutableSequence[str] = []
    syms: MutableSequence[str] = []

    def w_it() -> Iterator[str]:
        if words:
            word = "".join(reversed(words) if backwards else words)
            words.clear()
            yield word

    def s_it() -> Iterator[str]:
        if syms:
            sym = "".join(reversed(syms) if backwards else syms)
            syms.clear()
            yield sym

    for chr in reversed(chars) if backwards else chars:
        if is_word(unifying_chars, chr=chr):
            words.append(chr)
            yield from s_it()
        elif not chr.isspace():
            if include_syms:
                syms.append(chr)
            yield from w_it()
        else:
            yield from w_it()
            yield from s_it()

    yield from w_it()
    yield from s_it()


def tokenize(
    tokenization_limit: int,
    unifying_chars: AbstractSet[str],
    include_syms: bool,
    text: str,
) -> Iterator[str]:
    words = coalesce(
        unifying_chars, include_syms=include_syms, backwards=None, chars=text
    )
    return islice(words, tokenization_limit)
