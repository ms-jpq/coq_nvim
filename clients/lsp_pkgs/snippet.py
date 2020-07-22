from enum import Enum, auto
from itertools import chain
from string import ascii_letters, digits
from typing import Iterable, Iterator, List, Optional, Set, Tuple

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


def parse_escape(begin: str, it: Iterator[str], escapable_chars: Set[str]) -> str:
    assert begin == "\\"
    char = next(it, "")
    if char in escapable_chars:
        return char
    else:
        err = make_parse_err(
            condition="after \\", expected=escapable_chars, actual=char
        )
        raise err


# choice      ::= '${' int '|' text (',' text)* '|}'
def half_parse_choice(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "|"
    for char in it:
        if char == "\\":
            yield parse_escape(char, it, escapable_chars=_choice_escapable_chars)
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
def half_parse_place_holder(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == ":"
    yield from parse((), it, nested=True)


# choice | placeholder
# -- both starts with (int)
def parse_choices_n_placeholder(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin in _int_chars
    for char in it:
        if char in _int_chars:
            pass
        elif char == "|":
            yield from half_parse_choice(char, it)
            break
        elif char == ":":
            yield from half_parse_place_holder(char, it)
            break
        else:
            err = make_parse_err(
                condition="after |", expected=("0-9", "|", ":"), actual=char
            )
            raise err


def variable_substitution(name: str) -> Optional[str]:
    return ""


class VarType(Enum):
    naked = auto()  # '$' var
    simple = auto()  # '${' var }'
    arbitrary = auto()  # '${' var ':' any '}'
    decorated = auto()  # '${' var '/' regex '/' (format | text)+ '/' options '}'


# variable    ::= '$' var | '${' var }'
#                | '${' var ':' any '}'
#                | '${' var '/' regex '/' (format | text)+ '/' options '}'
def parse_variable(begin: str, it: Iterator[str], naked: bool) -> Iterator[str]:
    name_acc: List[str] = []
    if naked:
        # variable    ::= '$' var
        for char in chain((begin,), it):
            if char in _var_chars:
                name_acc.append(char)
            else:
                name = "".join(name_acc)
                var = variable_substitution(name)
                if var:
                    yield var
                else:
                    yield name
                yield from parse((char,), it, nested=False)
                break
    else:
        v_type = VarType.naked
        for char in chain((begin,), it):
            if char in _var_chars:
                name_acc.append(char)
            elif char == "}":
                v_type = VarType.simple
                break
            elif char == ":":
                v_type = VarType.arbitrary
                break
            elif char == "/":
                v_type = VarType.decorated
                break
            else:
                err = make_parse_err(
                    condition="parsing var", expected=("_", "a-z", "A-Z"), actual=char
                )
                raise err

        name = "".join(name_acc)
        var = variable_substitution(name)
        if v_type == VarType.simple:
            pass
        elif v_type == VarType.arbitrary:
            pass
        elif v_type == VarType.decorated:
            pass
        else:
            assert False


def parse_inner_scope(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "{"
    char = next(it, "")
    if char in _int_chars:
        yield from parse_choices_n_placeholder(char, it)
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
    elif char in _int_chars:
        # tabstop     ::= '$' int | '${' int '}'
        for char in it:
            if char in _int_chars:
                pass
            else:
                yield from parse((char,), it, nested=False)
                break
    elif char in _var_begin_chars:
        yield from parse_variable(char, it, naked=True)
    else:
        err = make_parse_err(condition="after $", expected=("{",), actual=char)
        raise err


def parse(prev_chars: Iterable[str], it: Iterator, nested: bool) -> Iterator[str]:
    for char in chain(prev_chars, it):
        if char == "\\":
            yield parse_escape(char, it, escapable_chars=_escapable_chars)
        elif nested and char == "}":
            break
        elif char == "$":
            yield from parse_scope(char, it)
        else:
            yield char


def parse_snippet(text: str) -> Tuple[str, str]:
    it = iter(text)
    new_prefix = "".join(parse((), it, nested=False))
    new_suffix = ""
    return new_prefix, new_suffix
