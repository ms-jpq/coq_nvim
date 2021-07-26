from asyncio.events import AbstractEventLoop
from asyncio.tasks import as_completed
from concurrent.futures import Executor
from itertools import chain
from typing import (
    AbstractSet,
    AsyncIterator,
    Iterable,
    Iterator,
    MutableSequence,
    Sequence,
    Union,
)
from unicodedata import east_asian_width

from std2.itertools import chunk_into

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


def _coalesce(
    text: Union[Sequence[str], str, bytes], unifying_chars: AbstractSet[str]
) -> Sequence[str]:
    if isinstance(text, bytes):
        chars: Iterable[str] = text.decode()
    elif isinstance(text, str):
        chars = text
    else:
        chars = chain.from_iterable(text)
    return tuple(coalesce(chars, unifying_chars=unifying_chars))


async def acoalesce(
    loop: AbstractEventLoop,
    ppool: Executor,
    text: Union[Sequence[str], str, bytes],
    unifying_chars: AbstractSet[str],
) -> Sequence[str]:
    return await loop.run_in_executor(ppool, _coalesce, text, unifying_chars)


async def acoalesce_lines(
    loop: AbstractEventLoop,
    ppool: Executor,
    lines: Sequence[str],
    unifying_chars: AbstractSet[str],
) -> Sequence[str]:
    async def cont() -> AsyncIterator[str]:
        cos = tuple(
            acoalesce(loop, ppool=ppool, text=chunk, unifying_chars=unifying_chars)
            for chunk in chunk_into(lines)
        )
        for fut in as_completed(cos):
            for word in await fut:
                yield word

    return [word async for word in cont()]

