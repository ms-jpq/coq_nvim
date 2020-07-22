from typing import Iterator, Tuple


def parse_snippet(text: str) -> Tuple[str, str]:
    dollar = False
    bracket = False
    it = iter(text)

    def pre() -> Iterator[str]:
        nonlocal dollar, bracket

        for char in it:
            if char == "$":
                dollar = True
            elif dollar:
                dollar = False
                if char == "{":
                    bracket = True
                    break
            else:
                yield char

    def post() -> Iterator[str]:
        nonlocal dollar, bracket

        for char in it:
            if char == "$":
                dollar = True
            elif dollar:
                dollar = False
                if char == "{":
                    bracket = True
            elif bracket:
                if char == "}":
                    bracket = False
            else:
                yield char

    new_prefix = "".join(pre())
    new_suffix = "".join(post())
    return new_prefix, new_suffix
