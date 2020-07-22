from typing import Iterator, Tuple


def parse_inner(it: Iterator[str]) -> Iterator[str]:
    printable = False
    for char in it:
        if char == "}":
            break
        elif printable:
            yield char
        elif char == ":":
            printable = True


def parse_snippet(text: str) -> Tuple[str, str]:
    it = iter(text)
    dollar = False

    def pre() -> Iterator[str]:
        nonlocal dollar

        for char in it:
            if char == "$":
                dollar = True
            elif dollar:
                dollar = False
                if char == "{":
                    yield from parse_inner(it)
                    break
            else:
                yield char

    def post() -> Iterator[str]:
        nonlocal dollar

        for char in it:
            if char == "$":
                dollar = True
            elif dollar:
                dollar = False
                if char == "{":
                    yield from parse_inner(it)
            else:
                yield char

    new_prefix = "".join(pre())
    new_suffix = "".join(post())
    return new_prefix, new_suffix
