from enum import Enum, auto
from itertools import chain
from string import ascii_letters, digits
from typing import Iterable, Iterator, List, Optional, Set, Tuple

#
# O(n) single pass LSP Parser:
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

    yield " "
    for char in it:
        if char == "\\":
            yield parse_escape(char, it, escapable_chars=_choice_escapable_chars)
        elif char == "|":
            char = next(it, "")
            if char == "}":
                yield " "
                break
            else:
                err = make_parse_err(condition="after |", expected=("}",), actual=char)
                raise err
        elif char == ",":
            yield " | "
        else:
            yield char


# placeholder ::= '${' int ':' any '}'
def half_parse_place_holder(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == ":"
    yield from parse((), it, nested=True)


# tabstop | choice | placeholder
# -- all starts with (int)
def parse_tcp(begin: str, it: Iterator[str]) -> Iterator[str]:
    it = chain((begin,), it)

    for char in it:
        if char in _int_chars:
            pass
        elif char == "}":
            # tabstop     ::= '$' int | '${' int '}'
            break
        elif char == "|":
            # choice      ::= '${' int '|' text (',' text)* '|}'
            yield from half_parse_choice(char, it)
            break
        elif char == ":":
            # placeholder ::= '${' int ':' any '}'
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
    it = chain((begin,), it)
    name_acc: List[str] = []

    if naked:
        # variable    ::= '$' var
        for char in it:
            if char in _var_chars:
                name_acc.append(char)
            else:
                name = "".join(name_acc)
                var = variable_substitution(name)
                yield var if var else name
                yield from parse((char,), it, nested=False)
                break
    else:
        v_type: Optional[VarType] = None
        for char in it:
            if char in _var_chars:
                name_acc.append(char)
            elif char == "}":
                v_type = VarType.simple
                break
            elif char == "/":
                v_type = VarType.decorated
                break
            elif char == ":":
                v_type = VarType.arbitrary
                break
            else:
                err = make_parse_err(
                    condition="parsing var", expected=("_", "a-z", "A-Z"), actual=char
                )
                raise err

        name = "".join(name_acc)
        var = variable_substitution(name)
        if v_type == VarType.simple:
            # '${' var }'
            yield var if var else name
        elif v_type == VarType.decorated:
            # '${' var '/' regex '/' (format | text)+ '/' options '}'
            yield var if var else name
            for char in it:
                if char == "\\":
                    _ = parse_escape(char, it, escapable_chars=_escapable_chars)
                elif char == "}":
                    break
        elif v_type == VarType.arbitrary:
            # '${' var ':' any '}'
            if var:
                yield var
            else:
                yield from parse((), it, nested=True)
        else:
            assert False
        yield from parse((), it, nested=False)


# ${...}
def parse_inner_scope(begin: str, it: Iterator[str]) -> Iterator[str]:
    assert begin == "{"

    char = next(it, "")
    if char in _int_chars:
        # tabstop | placeholder | choice
        yield from parse_tcp(char, it)
    elif char in _var_begin_chars:
        # variable
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


# any         ::= tabstop | placeholder | choice | variable | text
def parse(
    prev_chars: Iterable[str], it: Iterator, nested: bool, short_circuit: bool = False
) -> Iterator[str]:
    it = chain(prev_chars, it)

    for char in it:
        if char == "\\":
            yield parse_escape(char, it, escapable_chars=_escapable_chars)
        elif nested and char == "}":
            break
        elif char == "$":
            yield from parse_scope(char, it)
            if short_circuit:
                break
        else:
            yield char


def parse_snippet(text: str) -> Tuple[str, str]:
    it = iter(text)
    new_prefix = "".join(parse((), it, nested=False, short_circuit=True))
    new_suffix = "".join(parse((), it, nested=False))
    return new_prefix, new_suffix
