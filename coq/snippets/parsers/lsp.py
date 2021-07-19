from os.path import basename, dirname, splitext
from string import ascii_letters, ascii_lowercase, digits
from typing import AbstractSet, MutableSequence, Optional, Sequence

from ...shared.types import Context
from .parser import context_from, next_char, pushback_chars, raise_err, token_parser
from .types import (
    Begin,
    DummyBegin,
    End,
    Parsed,
    ParseInfo,
    ParserCtx,
    TokenStream,
    Unparsed,
)

#
# O(n) single pass LSP Parser:
# https://github.com/microsoft/language-server-protocol/blob/master/snippetSyntax.md
#


"""
any         ::= tabstop | placeholder | choice | variable | text
tabstop     ::= '$' int | '${' int '}'
placeholder ::= '${' int ':' any '}'
choice      ::= '${' int '|' text (',' text)* '|}'
variable    ::= '$' var | '${' var }'
                | '${' var ':' any '}'
                | '${' var '/' regex '/' (format | text)+ '/' options '}'
format      ::= '$' int | '${' int '}'
                | '${' int ':' '/upcase' | '/downcase' | '/capitalize' '}'
                | '${' int ':+' if '}'
                | '${' int ':?' if ':' else '}'
                | '${' int ':-' else '}' | '${' int ':' else '}'
regex       ::= JavaScript Regular Expression value (ctor-string)
options     ::= JavaScript Regular Expression option (ctor-options)
var         ::= [_a-zA-Z] [_a-zA-Z0-9]*
int         ::= [0-9]+
text        ::= .*
"""


_escapable_chars = {"\\", "$", "}"}
_regex_escape_chars = {"\\", "/"}
_choice_escapable_chars = _escapable_chars | {",", "|"}
_int_chars = {*digits}
_var_begin_chars = {*ascii_letters}
_var_chars = {*digits, *ascii_letters, "_"}
_regex_flag_chars = {*ascii_lowercase}


def _parse_escape(context: ParserCtx, *, escapable_chars: AbstractSet[str]) -> str:
    pos, char = next_char(context)
    assert char == "\\"

    pos, char = next_char(context)
    if char in escapable_chars:
        return char
    else:
        raise_err(
            text=context.text,
            pos=pos,
            condition="after \\",
            expected=escapable_chars,
            actual=char,
        )


# choice      ::= '${' int '|' text (',' text)* '|}'
def _half_parse_choice(context: ParserCtx) -> TokenStream:
    pos, char = next_char(context)
    assert char == "|"

    yield " "
    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            yield _parse_escape(context, escapable_chars=_choice_escapable_chars)
        elif char == "|":
            pos, char = next_char(context)
            if char == "}":
                yield " "
                yield End()
                break
            else:
                raise_err(
                    text=context.text,
                    pos=pos,
                    condition="after |",
                    expected=("}",),
                    actual=char,
                )
        elif char == ",":
            yield "|"
        else:
            yield char


# tabstop | choice | placeholder
# -- all starts with (int)
def _parse_tcp(context: ParserCtx) -> TokenStream:
    idx_acc: MutableSequence[str] = []

    for pos, char in context:
        if char in _int_chars:
            idx_acc.append(char)
        else:
            yield Begin(idx=int("".join(idx_acc)))
            if char == "}":
                # tabstop     ::= '$' int | '${' int '}'
                yield End()
                break
            elif char == "|":
                # choice      ::= '${' int '|' text (',' text)* '|}'
                pushback_chars(context, (pos, char))
                yield from _half_parse_choice(context)
                break
            elif char == ":":
                # placeholder ::= '${' int ':' any '}'
                context.state.depth += 1
                break
            else:
                raise_err(
                    text=context.text,
                    pos=pos,
                    condition="while parsing (tabstop | choice | placeholder)",
                    expected=("0-9", "|", ":"),
                    actual=char,
                )


def _variable_substitution(context: ParserCtx, *, name: str) -> Optional[str]:
    ctx = context.ctx
    row, _ = ctx.position

    if name == "TM_SELECTED_TEXT":
        return context.info.visual

    elif name == "TM_CURRENT_LINE":
        return ctx.line

    elif name == "TM_CURRENT_WORD":
        return ctx.words

    elif name == "TM_LINE_INDEX":
        return str(row)

    elif name == "TM_LINE_NUMBER":
        return str(row + 1)

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
def _parse_variable_naked(context: ParserCtx) -> TokenStream:
    name_acc: MutableSequence[str] = []

    for pos, char in context:
        if char in _var_chars:
            name_acc.append(char)
        else:
            name = "".join(name_acc)
            var = _variable_substitution(context, name=name)
            yield var if var is not None else name
            pushback_chars(context, (pos, char))
            break


# /' regex '/' (format | text)+ '/'
def _variable_decoration(
    context: ParserCtx, *, var: str, decoration: Sequence[str]
) -> TokenStream:
    text = "".join(decoration)
    yield var
    yield Unparsed(text=text)


# | '${' var '/' regex '/' (format | text)+ '/' options '}'
def _parse_variable_decorated(context: ParserCtx, var: str) -> TokenStream:
    pos, char = next_char(context)
    assert char == "/"

    decoration_acc = [char]
    seen = 1
    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            char = _parse_escape(context, escapable_chars=_regex_escape_chars)
            decoration_acc.append(char)
        elif char == "/":
            seen += 1
            if seen >= 3:
                for pos, char in context:
                    if char in _regex_flag_chars:
                        decoration_acc.append(char)
                    elif char == "}":
                        decoration = "".join(decoration_acc)
                        yield from _variable_decoration(
                            context, var=var, decoration=decoration
                        )
                        return
                    else:
                        raise_err(
                            text=context.text,
                            pos=pos,
                            condition="after /../../",
                            expected=("[a-z]"),
                            actual=char,
                        )
        else:
            pass


# variable    ::= '$' var | '${' var }'
#                | '${' var ':' any '}'
#                | '${' var '/' regex '/' (format | text)+ '/' options '}'
def _parse_variable_nested(context: ParserCtx) -> TokenStream:
    name_acc: MutableSequence[str] = []

    for pos, char in context:
        if char in _var_chars:
            name_acc.append(char)
        elif char == "}":
            # '${' var }'
            name = "".join(name_acc)
            var = _variable_substitution(context, name=name)
            yield var if var is not None else name
            break
        elif char == ":":
            # '${' var ':' any '}'
            name = "".join(name_acc)
            var = _variable_substitution(context, name=name)
            if var is not None:
                yield var
                context.state.depth += 1
                yield from _parse(context, shallow=True)
            else:
                yield DummyBegin()
                context.state.depth += 1
            break
        elif char == "/":
            # '${' var '/' regex '/' (format | text)+ '/' options '}'
            name = "".join(name_acc)
            pushback_chars(context, (pos, char))
            yield from _parse_variable_decorated(context, var=name)
            break
        else:
            raise_err(
                text=context.text,
                pos=pos,
                condition="parsing var",
                expected=("_", "a-z", "A-Z"),
                actual=char,
            )


# ${...}
def _parse_inner_scope(context: ParserCtx) -> TokenStream:
    pos, char = next_char(context)
    assert char == "{"

    pos, char = next_char(context)
    if char in _int_chars:
        # tabstop | placeholder | choice
        pushback_chars(context, (pos, char))
        yield from _parse_tcp(context)
    elif char in _var_begin_chars:
        # variable
        pushback_chars(context, (pos, char))
        yield from _parse_variable_nested(context)
    else:
        raise_err(
            text=context.text,
            pos=pos,
            condition="after ${",
            expected=("_", "0-9", "A-z"),
            actual=char,
        )


# $...
def _parse_scope(context: ParserCtx) -> TokenStream:
    pos, char = next_char(context)
    assert char == "$"

    pos, char = next_char(context)
    if char == "{":
        pushback_chars(context, (pos, char))
        yield from _parse_inner_scope(context)
    elif char in _int_chars:
        idx_acc = [char]
        # tabstop     ::= '$' int
        for pos, char in context:
            if char in _int_chars:
                idx_acc.append(char)
            else:
                yield Begin(idx=int("".join(idx_acc)))
                yield End()
                pushback_chars(context, (pos, char))
                break
    elif char in _var_begin_chars:
        pushback_chars(context, (pos, char))
        yield from _parse_variable_naked(context)
    else:
        raise_err(
            text=context.text,
            pos=pos,
            condition="after $",
            expected=("{",),
            actual=char,
        )


# any         ::= tabstop | placeholder | choice | variable | text
def _parse(context: ParserCtx, shallow: bool) -> TokenStream:
    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            yield _parse_escape(context, escapable_chars=_escapable_chars)
        elif context.state.depth and char == "}":
            yield End()
            context.state.depth -= 1
            if shallow:
                break
        elif char == "$":
            pushback_chars(context, (pos, char))
            yield from _parse_scope(context)
        else:
            yield char


def parser(context: Context, info: ParseInfo, snippet: str) -> Parsed:
    ctx = context_from(snippet, context=context, info=info)
    tokens = _parse(ctx, shallow=False)
    parsed = token_parser(ctx, stream=tokens)
    return parsed

