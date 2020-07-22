from string import ascii_letters, digits
from typing import Iterator, Tuple

_var_chars = {*digits, *ascii_letters, "_"}


def parse_inner(it: Iterator[str]) -> Iterator[str]:
    printable = False
    for char in it:
        if char == "\\":
            yield next(it, "")
        elif char == "}":
            break
        elif printable:
            yield char
        elif char == ":":
            printable = True


def parse_dollar(it: Iterator[str]) -> Iterator:
    for char in it:
        if char in _var_chars:
            pass
        elif char == "\\":
            yield next(it, "")
            break
        elif char == "$":
            yield from parse_dollar(it)
            break
        elif char == "{":
            yield from parse_inner(it)
            break
        else:
            yield char
            break


def parse_snippet(text: str) -> Tuple[str, str]:
    it = iter(text)

    def pre() -> Iterator[str]:

        for char in it:
            if char == "\\":
                yield next(it, "")
            elif char == "$":
                yield from parse_dollar(it)
                break
            else:
                yield char

    def post() -> Iterator[str]:
        for char in it:
            if char == "\\":
                yield next(it, "")
            elif char == "$":
                yield from parse_dollar(it)
            else:
                yield char

    new_prefix = "".join(pre())
    new_suffix = "".join(post())
    return new_prefix, new_suffix
