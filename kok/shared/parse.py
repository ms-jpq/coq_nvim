from typing import Iterable, Iterator, List, Set


def normalize(text: str) -> str:
    return text.casefold()


def is_word(char: str, unifying_chars: Set[str]) -> bool:
    return char in unifying_chars or char.isalnum()


def is_sym(char: str) -> bool:
    return not char.isalnum() and not char.isspace()


def coalesce(
    chars: Iterable[str], max_length: int, unifying_chars: Set[str]
) -> Iterator[str]:
    curr: List[str] = []
    for char in chars:
        if is_word(char, unifying_chars=unifying_chars):
            curr.append(char)
        elif curr:
            word = "".join(curr)
            curr.clear()
            wl = len(word)
            if wl <= max_length:
                yield word

    if curr:
        word = "".join(curr)
        wl = len(word)
        if wl >= max_length:
            yield word
