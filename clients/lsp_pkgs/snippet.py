from string import ascii_letters, digits
from typing import Iterable, Iterator, Optional, Set, Tuple

#
# Parser for
# https://github.com/microsoft/language-server-protocol/blob/master/snippetSyntax.md
#


class ParseError(Exception):
    pass


_escapable_chars = {"\\", "$", "}"}
_choice_escapable_chars = _escapable_chars | {",", "|"}
_int_chars = {*digits}
_var_begin_chars = {*ascii_letters}
_var_chars = {*digits, *ascii_letters, "_"}


def make_parse_err(condition: str, expected: Iterable[str], actual: str) -> ParseError:
    char = f"'{actual}'" if actual else "EOF"
    enumerated = ", ".join(map(lambda c: f"'{c}'", expected))
    msg = f"Unexpected char found {condition}. expected: {enumerated}. found: {char}"
    return ParseError(msg)


def parse_escape(
    begin: str, it: Iterator[str], escapable_chars: Set[str]
) -> Iterator[str]:
    assert begin == "\\"
    char = next(it, "")
    if char in escapable_chars:
        yield char
    else:
        err = make_parse_err(
            condition="after \\", expected=escapable_chars, actual=char
        )
        raise err


# choice      ::= '${' int '|' text (',' text)* '|}'
def parse_choice(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "|"
    for char in it:
        if char == "\\":
            yield from parse_escape(char, it, escapable_chars=_choice_escapable_chars)
        elif char == "|":
            char = next(it, "")
            if char == "}":
                break
            else:
                err = make_parse_err(condition="after |", expected=("}",), actual=char)
                raise err
        else:
            yield char


# placeholder ::= '${' int ':' any '}'
def parse_place_holder(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == ":"
    for char in it:
        if char == "\\":
            yield from parse_escape(char, it, escapable_chars=_escapable_chars)
        elif char == "}":
            break
        else:
            # TODO This is wrong, needs to handle ANY
            yield char


# choice | placeholder
# -- both starts with (int)
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


def variable_substitution(name: str) -> Optional[str]:
    return ""



# variable    ::= '$' var | '${' var }'
#                | '${' var ':' any '}'
#                | '${' var '/' regex '/' (format | text)+ '/' options '}'
def parse_variable(begin: str, it: Iterator[str], naked: bool) -> Iterator[str]:
    name_acc = [begin]
    if naked:
        for char in it:
            if char in _var_chars:
                name_acc.append(char)
            else:
                name = "".join(name_acc)
                var = variable_substitution(name)
                if var:
                    yield var
                else:
                    yield name
                yield char
                yield from parse(it)
                break
    else:
        ignore_tail = False
        for char in it:
            if char == "}":
                name = "".join(name_acc)
                var = variable_substitution(name)
                if var:
                    yield var
                else:
                    yield name
                yield from parse(it)
                break
            elif ignore_tail:
                pass
            elif char in _var_chars:
                name_acc.append(char)
            elif char == ":":
                name = "".join(name_acc)
                var = variable_substitution(name)
                if var:
                    yield var
                else:
                    yield ""
            elif char == "/":
                # ignore format
                ignore_tail = True


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


def parse(it: Iterator) -> Iterator[str]:
    for char in it:
        if char == "\\":
            yield from parse_escape(char, it, escapable_chars=_escapable_chars)
        elif char == "$":
            yield from parse_scope(char, it)
        else:
            yield char


def parse_snippet(text: str) -> Tuple[str, str]:
    it = iter(text)
    new_prefix = "".join(parse(it))
    new_suffix = ""
    return new_prefix, new_suffix
