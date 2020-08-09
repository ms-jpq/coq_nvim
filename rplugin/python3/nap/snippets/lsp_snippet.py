from dataclasses import dataclass
from itertools import chain
from os import linesep
from os.path import basename, dirname, splitext
from string import ascii_letters, digits
from typing import (
    Dict,
    Iterable,
    Iterator,
    List,
    Optional,
    Sequence,
    Set,
    Tuple,
    Union,
    cast,
)

from ..shared.types import Context

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
OutStream = Iterator[Union[str, Tuple[int]]]


@dataclass(frozen=False)
class ParseContext:
    text: str
    it: CharStream
    vals: Context
    depth: int = 0
    has_split: bool = False


class ParseError(Exception):
    pass


_escapable_chars = {"\\", "$", "}"}
_choice_escapable_chars = _escapable_chars | {",", "|"}
_int_chars = {*digits}
_var_begin_chars = {*ascii_letters}
_var_chars = {*digits, *ascii_letters, "_"}


def next_char(context: ParseContext) -> IChar:
    return next(context.it, (-1, ""))


def pushback_chars(context: ParseContext, *vals: IChar) -> None:
    context.it = chain(iter(vals), context.it)


def make_parse_err(
    text: str, index: int, condition: str, expected: Iterable[str], actual: str
) -> ParseError:
    band = 5
    char = f"'{actual}'" if actual else "EOF"
    enumerated = ", ".join(map(lambda c: f"'{c}'", expected))
    msg = f"- Unexpected char found {condition}. expected: {enumerated}. found: {char}"
    ctx = "" if index == -1 else f"{linesep}{text[index-band:index+band+1]}"
    return ParseError(f"{msg}{ctx}")


def parse_escape(context: ParseContext, *, escapable_chars: Set[str]) -> str:
    index, char = next_char(context)
    assert char == "\\"

    index, char = next_char(context)
    if char in escapable_chars:
        return char
    else:
        err = make_parse_err(
            text=context.text,
            index=index,
            condition="after \\",
            expected=escapable_chars,
            actual=char,
        )
        raise err


# choice      ::= '${' int '|' text (',' text)* '|}'
def half_parse_choice(context: ParseContext) -> OutStream:
    index, char = next_char(context)
    assert char == "|"

    yield " "
    for index, char in context.it:
        if char == "\\":
            pushback_chars(context, (index, char))
            yield parse_escape(context, escapable_chars=_choice_escapable_chars)
        elif char == "|":
            index, char = next_char(context)
            if char == "}":
                yield " "
                break
            else:
                err = make_parse_err(
                    text=context.text,
                    index=index,
                    condition="after |",
                    expected=("}",),
                    actual=char,
                )
                raise err
        elif char == ",":
            yield " | "
        else:
            yield char


# placeholder ::= '${' int ':' any '}'
def half_parse_place_holder(context: ParseContext) -> OutStream:
    _, char = next_char(context)
    assert char == ":"

    context.depth += 1
    yield from parse(context)


# tabstop | choice | placeholder
# -- all starts with (int)
def parse_tcp(context: ParseContext) -> OutStream:
    idx_acc: List[str] = []

    for index, char in context.it:
        if char in _int_chars:
            idx_acc.append(char)
        else:
            yield (int("".join(idx_acc)),)
            if char == "}":
                # tabstop     ::= '$' int | '${' int '}'
                break
            elif char == "|":
                # choice      ::= '${' int '|' text (',' text)* '|}'
                pushback_chars(context, (index, char))
                yield from half_parse_choice(context)
                break
            elif char == ":":
                # placeholder ::= '${' int ':' any '}'
                pushback_chars(context, (index, char))
                yield from half_parse_place_holder(context)
                break
            else:
                err = make_parse_err(
                    text=context.text,
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
        return basename(ctx.filename)

    elif name == "TM_FILENAME_BASE":
        fn, _ = splitext(basename(ctx.filename))
        return fn

    elif name == "TM_DIRECTORY":
        return dirname(ctx.filename)

    elif name == "TM_FILEPATH":
        return ctx.filename

    else:
        return None


# variable    ::= '$' var
def parse_variable_naked(context: ParseContext) -> OutStream:
    index, char = next_char(context)
    assert char == "$"

    name_acc: List[str] = []

    for index, char in context.it:
        if char in _var_chars:
            name_acc.append(char)
        else:
            name = "".join(name_acc)
            var = variable_substitution(context, name=name)
            yield var if var else name
            pushback_chars(context, (index, char))
            yield from parse(context)
            break


# /' regex '/' (format | text)+ '/'
def variable_decoration(
    context: ParseContext, *, var: str, decoration: Sequence[str]
) -> str:
    return var


# | '${' var '/' regex '/' (format | text)+ '/' options '}'
def parsed_variable_decorated(context: ParseContext, *, name: str) -> OutStream:
    index, char = next_char(context)
    assert char == "/"

    var = variable_substitution(context, name=name)

    for index, char in context.it:
        decoration = [char]
        if char == "\\":
            pushback_chars(context, (index, char))
            c = parse_escape(context, escapable_chars=_escapable_chars)
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
def parse_variable_nested(context: ParseContext) -> OutStream:
    name_acc: List[str] = []

    for index, char in context.it:
        if char in _var_chars:
            name_acc.append(char)
        elif char == "}":
            # '${' var }'
            name = "".join(name_acc)
            var = variable_substitution(context, name=name)
            yield var if var else name
            break
        elif char == "/":
            # '${' var '/' regex '/' (format | text)+ '/' options '}'
            name = "".join(name_acc)
            pushback_chars(context, (index, char))
            yield from parsed_variable_decorated(context, name=name)
            break
        elif char == ":":
            # '${' var ':' any '}'
            name = "".join(name_acc)
            var = variable_substitution(context, name=name)
            if var:
                yield var
            else:
                context.depth += 1
                yield from parse(context)
            break
        else:
            err = make_parse_err(
                text=context.text,
                index=index,
                condition="parsing var",
                expected=("_", "a-z", "A-Z"),
                actual=char,
            )
            raise err


# ${...}
def parse_inner_scope(context: ParseContext) -> OutStream:
    index, char = next_char(context)
    assert char == "{"

    index, char = next_char(context)
    if char in _int_chars:
        # tabstop | placeholder | choice
        pushback_chars(context, (index, char))
        yield from parse_tcp(context)
    elif char in _var_begin_chars:
        # variable
        pushback_chars(context, (index, char))
        yield from parse_variable_nested(context)
    else:
        err = make_parse_err(
            text=context.text,
            index=index,
            condition="after {",
            expected=("_", "0-9", "a-z", "A-Z"),
            actual=char,
        )
        raise err


# $...
def parse_scope(context: ParseContext) -> OutStream:
    index, char = next_char(context)
    assert char == "$"

    index, char = next_char(context)
    if char == "{":
        pushback_chars(context, (index, char))
        yield from parse_inner_scope(context)
    elif char in _int_chars:
        idx_acc: List[str] = [char]
        # tabstop     ::= '$' int
        for index, char in context.it:
            if char in _int_chars:
                idx_acc.append(char)
            else:
                yield (int("".join(idx_acc)),)
                pushback_chars(context, (index, char))
                yield from parse(context)
                break
    elif char in _var_begin_chars:
        pushback_chars(context, (index, char))
        yield from parse_variable_naked(context)
    else:
        err = make_parse_err(
            text=context.text,
            index=index,
            condition="after $",
            expected=("{",),
            actual=char,
        )
        raise err


# any         ::= tabstop | placeholder | choice | variable | text
def parse(context: ParseContext) -> OutStream:
    for index, char in context.it:
        if char == "\\":
            pushback_chars(context, (index, char))
            yield parse_escape(context, escapable_chars=_escapable_chars)
        elif context.depth and char == "}":
            context.depth -= 1
        elif char == "$":
            pushback_chars(context, (index, char))
            yield from parse_scope(context)
        else:
            yield char


def parse_snippet(ctx: Context, text: str) -> Tuple[str, str]:
    context = ParseContext(text=text, it=enumerate(text), vals=ctx)
    location: Dict[int, int] = {}

    def cont() -> Iterator[str]:
        i = 0
        for x in parse(context):
            if type(x) is tuple:
                place, *_ = cast(Tuple[int], x)
                location[place] = i
            else:
                yield cast(str, x)
                i += len(x)

    text = "".join(cont())
    smol_idx = location[min((location))] if location else len(text)
    new_prefix = text[:smol_idx]
    new_suffix = text[smol_idx:]
    return new_prefix, new_suffix
