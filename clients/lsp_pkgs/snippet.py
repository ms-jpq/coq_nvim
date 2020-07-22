from string import ascii_letters, digits
from typing import Iterable, Iterator, Tuple


# Parser for
# https://github.com/microsoft/language-server-protocol/blob/master/snippetSyntax.md
#
# The ordering of functions in this file is upside down
#
class ParseError(Exception):
    pass


_escapable_chars = {"\\", "$", "}"}
_int_chars = {*digits}
_var_begin_chars = {*ascii_letters}
_var_chars = {*digits, *ascii_letters, "_"}


def make_parse_err(condition: str, expected: Iterable[str], actual: str) -> ParseError:
    char = f"'{actual}'" if actual else "EOF"
    enumerated = ", ".join(map(lambda c: f"'{c}'", expected))
    msg = f"Unexpected char found {condition}. expected: {enumerated}. found: {char}"
    return ParseError(msg)


def parse(it: Iterator) -> Iterator[str]:
    for char in it:
        if char == "\\":
            yield from parse_escape(char, it)
        elif char == "$":
            yield from parse_scope(char, it)
        else:
            yield char


def parse_escape(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "\\"
    char = next(it, "")
    if char in _escapable_chars:
        yield char
    else:
        err = make_parse_err(
            condition="after \\", expected=_escapable_chars, actual=char
        )
        raise err


def parse_scope(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "$"
    char = next(it, "")
    if char == "{":
        yield from parse_inner_scope(char, it)
    elif char in _int_chars:  # tabstop -- discard
        for char in it:
            if char in _int_chars:
                pass
            else:
                yield from parse(it)
                break
    elif char in _var_begin_chars:
        yield from parse_variable(char, it, naked=True)
    else:
        err = make_parse_err(condition="after $", expected=("{",), actual=char)
        raise err


def parse_inner_scope(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "{"
    char = next(it, "")
    if char in _int_chars:
        yield from parse_cp(char, it)
    elif char in _var_begin_chars:
        yield from parse_variable(char, it, naked=False)
    else:
        err = make_parse_err(
            condition="after {", expected=("_", "0-9", "a-z", "A-Z"), actual=char
        )
        raise err


def parse_cp(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin in _int_chars
    for char in it:
        if char in _int_chars:
            pass
        elif char == "|":
            yield from parse_choice(char, it)
            break
        elif char == ":":
            yield from parse_place_holder(char, it)
            break
        else:
            err = make_parse_err(
                condition="after |", expected=("0-9", "|", ":"), actual=char
            )
            raise err


def parse_choice(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "|"
    for char in it:
        if char == "|":
            char = next(it, "")
            if char == "}":
                break
            else:
                err = make_parse_err(condition="after |", expected=("}",), actual=char)
                raise err
        else:
            yield char


def parse_place_holder(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == ":"
    for char in it:
        if char == "}":
            break
        else:
            yield char


def parse_variable(begin: str, it: Iterator[str], naked: bool) -> Iterator[str]:
    name_acc = [begin]
    if naked:
        for char in it:
            if char in _var_chars:
                name_acc.append(char)
            else:
                name = "".join(name_acc)
                yield from variable_substitution(name)
                yield from parse(it)
                break
    else:
        ignore_tail = False
        for char in it:
            if char == "}":
                name = "".join(name_acc)
                yield from variable_substitution(name)
                yield from parse(it)
                break
            elif ignore_tail:
                pass
            elif char in _var_chars:
                name_acc.append(char)
            elif char == ":":
                ignore_tail = True
            elif char == "/":
                ignore_tail = True


def variable_substitution(name: str) -> Iterator[str]:
    yield name


def parse_snippet(text: str) -> Tuple[str, str]:
    it = iter(text)

    def pre() -> Iterator[str]:
        for char in it:
            if char == "\\":
                yield from parse_escape(char, it)
            elif char == "$":
                yield from parse_scope(char, it)
                break
            else:
                yield char

    new_prefix = "".join(parse(it))
    new_suffix = ""
    return new_prefix, new_suffix
