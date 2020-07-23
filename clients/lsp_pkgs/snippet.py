from collections import OrderedDict
from dataclasses import dataclass, field
from itertools import chain
from os.path import basename, dirname, splitext
from string import ascii_letters, digits
from typing import Any, Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple

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

IChar = Tuple[int, str]
CharStream = Iterator[IChar]


@dataclass(frozen=False)
class ParseContext:
    vals: Context
    depth: int = 0
    tags: Dict[str, Any] = field(default_factory=OrderedDict)


class ParseError(Exception):
    pass


_escapable_chars = {"\\", "$", "}"}
_choice_escapable_chars = _escapable_chars | {",", "|"}
_int_chars = {*digits}
_var_begin_chars = {*ascii_letters}
_var_chars = {*digits, *ascii_letters, "_"}


def next_char(it: CharStream) -> IChar:
    return next(it, (-1, ""))


def pushback_chars(it: CharStream, *vals: IChar) -> CharStream:
    return chain(iter(vals), it)


def make_parse_err(
    index: int, condition: str, expected: Iterable[str], actual: str
) -> ParseError:
    idx = "EOF" if index == -1 else index
    char = f"'{actual}'" if actual else "EOF"
    enumerated = ", ".join(map(lambda c: f"'{c}'", expected))
    msg = f"@{idx} - Unexpected char found {condition}. expected: {enumerated}. found: {char}"
    return ParseError(msg)


def parse_escape(begin: IChar, it: CharStream, escapable_chars: Set[str]) -> str:
    _, char = begin
    assert char == "\\"

    index, char = next_char(it)
    if char in escapable_chars:
        return char
    else:
        err = make_parse_err(
            index=index, condition="after \\", expected=escapable_chars, actual=char
        )
        raise err


# choice      ::= '${' int '|' text (',' text)* '|}'
def half_parse_choice(
    context: ParseContext, *, begin: IChar, it: CharStream
) -> Iterator[str]:
    _, char = begin
    assert char == "|"

    yield " "
    for index, char in it:
        if char == "\\":
            yield parse_escape(
                (index, char), it=it, escapable_chars=_choice_escapable_chars
            )
        elif char == "|":
            index, char = next_char(it)
            if char == "}":
                yield " "
                break
            else:
                err = make_parse_err(
                    index=index, condition="after |", expected=("}",), actual=char
                )
                raise err
        elif char == ",":
            yield " | "
        else:
            yield char


# placeholder ::= '${' int ':' any '}'
def half_parse_place_holder(
    context: ParseContext, *, begin: IChar, it: CharStream
) -> Iterator[str]:
    _, char = begin
    assert char == ":"
    context.depth += 1
    yield from parse(context, prev_chars=(), it=it)


# tabstop | choice | placeholder
# -- all starts with (int)
def parse_tcp(context: ParseContext, *, begin: IChar, it: CharStream) -> Iterator[str]:
    it = pushback_chars(it, begin)

    for index, char in it:
        if char in _int_chars:
            pass
        elif char == "}":
            # tabstop     ::= '$' int | '${' int '}'
            break
        elif char == "|":
            # choice      ::= '${' int '|' text (',' text)* '|}'
            yield from half_parse_choice(context, begin=(index, char), it=it)
            break
        elif char == ":":
            # placeholder ::= '${' int ':' any '}'
            yield from half_parse_place_holder(context, begin=(index, char), it=it)
            break
        else:
            err = make_parse_err(
                index=index,
                condition="after |",
                expected=("0-9", "|", ":"),
                actual=char,
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


# variable    ::= '$' var
def parse_variable_naked(
    context: ParseContext, *, begin: IChar, it: CharStream
) -> Iterator[str]:
    it = pushback_chars(it, begin)
    name_acc: List[str] = []

    for index, char in it:
        if char in _var_chars:
            name_acc.append(char)
        else:
            name = "".join(name_acc)
            var = variable_substitution(context, name=name)
            yield var if var else name
            yield from parse(context, prev_chars=((index, char),), it=it)
            break


def parsed_variable_decorated(
    context: ParseContext, *, begin: IChar, it: CharStream, name: str
) -> Iterator[str]:
    index, char = begin
    assert char == "/"

    var = variable_substitution(context, name=name)

    for index, char in it:
        decoration: List[str] = []
        if char == "\\":
            c = parse_escape((index, char), it, escapable_chars=_escapable_chars)
            decoration.append(c)
        elif char == "}":
            yield variable_decoration(
                context=context, var=var, decoration=decoration
            ) if var else name
            break
        else:
            decoration.append(char)


# variable    ::= '$' var | '${' var }'
#                | '${' var ':' any '}'
#                | '${' var '/' regex '/' (format | text)+ '/' options '}'
def parse_variable_nested(
    context: ParseContext, *, begin: IChar, it: CharStream
) -> Iterator[str]:
    it = pushback_chars(it, begin)
    name_acc: List[str] = []

    for index, char in it:
        if char in _var_chars:
            name_acc.append(char)
        elif char == "}":
            # '${' var }'
            name = "".join(name_acc)
            var = variable_substitution(context, name=name)
            break
        elif char == "/":
            # '${' var '/' regex '/' (format | text)+ '/' options '}'
            name = "".join(name_acc)
            yield from parsed_variable_decorated(
                context, begin=(index, char), it=it, name=name
            )
            break
        elif char == ":":
            # '${' var ':' any '}'
            name = "".join(name_acc)
            var = variable_substitution(context, name=name)
            if var:
                yield var
            else:
                context.depth += 1
                yield from parse(context, prev_chars=(), it=it)
            break
        else:
            err = make_parse_err(
                index=index,
                condition="parsing var",
                expected=("_", "a-z", "A-Z"),
                actual=char,
            )
            raise err
    yield from parse(context, prev_chars=(), it=it)


# ${...}
def parse_inner_scope(
    context: ParseContext, *, begin: IChar, it: CharStream
) -> Iterator[str]:
    index, char = begin
    assert char == "{"

    index, char = next_char(it)
    if char in _int_chars:
        # tabstop | placeholder | choice
        yield from parse_tcp(context, begin=(index, char), it=it)
    elif char in _var_begin_chars:
        # variable
        yield from parse_variable_nested(context, begin=(index, char), it=it)
    else:
        err = make_parse_err(
            index=index,
            condition="after {",
            expected=("_", "0-9", "a-z", "A-Z"),
            actual=char,
        )
        raise err


def parse_scope(
    context: ParseContext, *, begin: IChar, it: CharStream
) -> Iterator[str]:
    index, char = begin
    assert char == "$"

    index, char = next_char(it)
    if char == "{":
        yield from parse_inner_scope(context, begin=(index, char), it=it)
    elif char in _int_chars:
        # tabstop     ::= '$' int | '${' int '}'
        for index, char in it:
            if char in _int_chars:
                pass
            else:
                yield from parse(context, prev_chars=((index, char),), it=it)
                break
    elif char in _var_begin_chars:
        yield from parse_variable_naked(context, begin=(index, char), it=it)
    else:
        err = make_parse_err(
            index=index, condition="after $", expected=("{",), actual=char
        )
        raise err


# any         ::= tabstop | placeholder | choice | variable | text
def parse(
    context: ParseContext, *, prev_chars: Iterable[IChar], it: CharStream,
) -> Iterator[str]:
    it = pushback_chars(it, *prev_chars)

    for index, char in it:
        if char == "\\":
            yield parse_escape((index, char), it, escapable_chars=_escapable_chars)
        elif context.depth and char == "}":
            context.depth -= 1
        elif char == "$":
            yield from parse_scope(context, begin=(index, char), it=it)
        else:
            yield char


def parse_snippet(ctx: Context, text: str) -> Tuple[str, str]:
    it = enumerate(text)
    context = ParseContext(vals=ctx)
    try:
        parsed = "".join(parse(context, prev_chars=(), it=it))
    except ParseError:
        return text, ""
    else:
        new_prefix = parsed
        new_suffix = ""
        return new_prefix, new_suffix
