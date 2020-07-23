from dataclasses import dataclass
from enum import Enum, auto
from itertools import chain
from os.path import basename, dirname, splitext
from string import ascii_letters, digits
from typing import Iterable, Iterator, List, Optional, Sequence, Set, Tuple

from ..pkgs.fc_types import Context

#
# O(n) single pass LSP Parser:
# https://github.com/microsoft/language-server-protocol/blob/master/snippetSyntax.md
#


# """
# any         ::= tabstop | placeholder | choice | variable | text
# tabstop     ::= '$' int | '${' int '}'
# placeholder ::= '${' int ':' any '}'
# choice      ::= '${' int '|' text (',' text)* '|}'
# variable    ::= '$' var | '${' var }'
#                 | '${' var ':' any '}'
#                 | '${' var '/' regex '/' (format | text)+ '/' options '}'
# format      ::= '$' int | '${' int '}'
#                 | '${' int ':' '/upcase' | '/downcase' | '/capitalize' '}'
#                 | '${' int ':+' if '}'
#                 | '${' int ':?' if ':' else '}'
#                 | '${' int ':-' else '}' | '${' int ':' else '}'
# regex       ::= JavaScript Regular Expression value (ctor-string)
# options     ::= JavaScript Regular Expression option (ctor-options)
# var         ::= [_a-zA-Z] [_a-zA-Z0-9]*
# int         ::= [0-9]+
# text        ::= .*
# """


@dataclass(frozen=False)
class ParseContext:
    vals: Context
    depth: int = 0


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
def half_parse_choice(
    context: ParseContext, *, begin: str, it: Iterator[str]
) -> Iterator[str]:
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
def half_parse_place_holder(
    context: ParseContext, *, begin: str, it: Iterator[str]
) -> Iterator[str]:
    assert begin == ":"
    context.depth += 1
    yield from parse(context, prev_chars=(), it=it)


# tabstop | choice | placeholder
# -- all starts with (int)
def parse_tcp(context: ParseContext, *, begin: str, it: Iterator[str]) -> Iterator[str]:
    it = chain((begin,), it)

    for char in it:
        if char in _int_chars:
            pass
        elif char == "}":
            # tabstop     ::= '$' int | '${' int '}'
            break
        elif char == "|":
            # choice      ::= '${' int '|' text (',' text)* '|}'
            yield from half_parse_choice(context, begin=char, it=it)
            break
        elif char == ":":
            # placeholder ::= '${' int ':' any '}'
            yield from half_parse_place_holder(context, begin=char, it=it)
            break
        else:
            err = make_parse_err(
                condition="after |", expected=("0-9", "|", ":"), actual=char
            )
            raise err


def variable_substitution(context: ParseContext, *, name: str) -> Optional[str]:
    ctx = context.vals
    if name == "TM_SELECTED_TEXT":
        return None
    elif name == "TM_CURRENT_LINE":
        return ctx.line
    elif name == "TM_CURRENT_WORD":
        return ctx.alnums
    elif name == "TM_LINE_INDEX":
        return str(ctx.position.row)
    elif name == "TM_LINE_NUMBER":
        return str(ctx.position.row + 1)
    elif name == "TM_FILENAME":
        fn = basename(ctx.filename)
        return fn
    elif name == "TM_FILENAME_BASE":
        fn, _ = splitext(basename(ctx.filename))
        return fn
    elif name == "TM_DIRECTORY":
        return dirname(ctx.filename)
    elif name == "TM_FILEPATH":
        return ctx.filename
    else:
        return None


def variable_decoration(
    context: ParseContext, *, var: str, decoration: Sequence[str]
) -> str:
    return var


class VarType(Enum):
    naked = auto()  # '$' var
    simple = auto()  # '${' var }'
    arbitrary = auto()  # '${' var ':' any '}'
    decorated = auto()  # '${' var '/' regex '/' (format | text)+ '/' options '}'


# variable    ::= '$' var
def parse_variable_naked(
    context: ParseContext, *, begin: str, it: Iterator[str]
) -> Iterator[str]:
    it = chain((begin,), it)
    name_acc: List[str] = []

    for char in it:
        if char in _var_chars:
            name_acc.append(char)
        else:
            name = "".join(name_acc)
            var = variable_substitution(context, name=name)
            yield var if var else name
            yield from parse(context, prev_chars=(char,), it=it)
            break


# variable    ::= '$' var | '${' var }'
#                | '${' var ':' any '}'
#                | '${' var '/' regex '/' (format | text)+ '/' options '}'
def parse_variable_nested(
    context: ParseContext, *, begin: str, it: Iterator[str]
) -> Iterator[str]:
    it = chain((begin,), it)
    name_acc: List[str] = []

    v_type: Optional[VarType] = None
    for char in it:
        if char in _var_chars:
            name_acc.append(char)
        elif char == "}":
            # '${' var }'
            v_type = VarType.simple
            break
        elif char == "/":
            # '${' var '/' regex '/' (format | text)+ '/' options '}'
            v_type = VarType.decorated
            break
        elif char == ":":
            # '${' var ':' any '}'
            v_type = VarType.arbitrary
            break
        else:
            err = make_parse_err(
                condition="parsing var", expected=("_", "a-z", "A-Z"), actual=char
            )
            raise err

    name = "".join(name_acc)
    var = variable_substitution(context, name=name)

    if v_type == VarType.simple:
        # '${' var }'
        yield var if var else name
    elif v_type == VarType.decorated:
        # '${' var '/' regex '/' (format | text)+ '/' options '}'
        for char in it:
            decoration: List[str] = []
            if char == "\\":
                c = parse_escape(char, it, escapable_chars=_escapable_chars)
                decoration.append(c)
            elif char == "}":
                yield variable_decoration(
                    context=context, var=var, decoration=decoration
                ) if var else name
                break
            else:
                decoration.append(char)
    elif v_type == VarType.arbitrary:
        # '${' var ':' any '}'
        if var:
            yield var
        else:
            context.depth += 1
            yield from parse(context, prev_chars=(), it=it)
    else:
        assert False
    yield from parse(context, prev_chars=(), it=it)


# ${...}
def parse_inner_scope(
    context: ParseContext, *, begin: str, it: Iterator[str]
) -> Iterator[str]:
    assert begin == "{"

    char = next(it, "")
    if char in _int_chars:
        # tabstop | placeholder | choice
        yield from parse_tcp(context, begin=char, it=it)
    elif char in _var_begin_chars:
        # variable
        yield from parse_variable_nested(context, begin=char, it=it)
    else:
        err = make_parse_err(
            condition="after {", expected=("_", "0-9", "a-z", "A-Z"), actual=char
        )
        raise err


def parse_scope(
    context: ParseContext, *, begin: str, it: Iterator[str]
) -> Iterator[str]:
    assert begin == "$"

    char = next(it, "")
    if char == "{":
        yield from parse_inner_scope(context, begin=char, it=it)
    elif char in _int_chars:
        # tabstop     ::= '$' int | '${' int '}'
        for char in it:
            if char in _int_chars:
                pass
            else:
                yield from parse(context, prev_chars=(char,), it=it)
                break
    elif char in _var_begin_chars:
        yield from parse_variable_naked(context, begin=char, it=it)
    else:
        err = make_parse_err(condition="after $", expected=("{",), actual=char)
        raise err


# any         ::= tabstop | placeholder | choice | variable | text
def parse(
    context: ParseContext,
    *,
    prev_chars: Iterable[str],
    it: Iterator,
    short_circuit: bool = False,
) -> Iterator[str]:
    it = chain(prev_chars, it)

    for char in it:
        if char == "\\":
            yield parse_escape(char, it, escapable_chars=_escapable_chars)
        elif context.depth and char == "}":
            context.depth -= 1
        elif char == "$":
            yield from parse_scope(context, begin=char, it=it)
            if short_circuit:
                break
        else:
            yield char


def parse_snippet(ctx: Context, text: str) -> Tuple[str, str]:
    it = iter(text)
    context = ParseContext(vals=ctx)
    try:
        new_prefix = "".join(parse(context, prev_chars=(), it=it, short_circuit=True))
        new_suffix = "".join(parse(context, prev_chars=(), it=it))
    except ParseError:
        return text, ""
    else:
        return new_prefix, new_suffix
