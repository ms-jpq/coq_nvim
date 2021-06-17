from dataclasses import dataclass
from string import ascii_letters, ascii_lowercase, digits
from typing import List, Optional, Set

from ...shared.types import Context
from .parser import (
    context_from,
    next_char,
    pushback_chars,
    raise_err,
    token_parser,
)
from .types import (
    Begin,
    DummyBegin,
    End,
    ParserCtx,
    Parsed,
    Token,
    TokenStream,
    Unparsed,
)

"""
any          ::= tabstop | variable | placeholder | text
tabstop      ::= '$' int | '${' int '}'
placeholder  ::= '${' int ':' ('#:'? any | regexreplace) '}'
variable     ::= '${' var '}' | '${' var ':' any '}'
regexreplace ::= '/' text '/' text '/' [a-z]*
lang         ::= '`' text  '`' | '`!' [a-z] text '`'
var          ::= ([A-z] | '$') [A-z]+
int          ::= [0-9]+
text         ::= .*
"""


@dataclass(frozen=False)
class Local:
    depth: int


_escapable_chars = {"\\", "$", "}"}
_regex_escape_chars = {"/"}
_lang_escape_chars = {"`"}
_int_chars = {*digits}
_var_begin_chars = {*ascii_letters, "$"}
_lang_begin_chars = {*ascii_lowercase}
_regex_flag_chars = {*ascii_lowercase}


def _parse_escape(context: ParserCtx[Local], *, escapable_chars: Set[str]) -> str:
    pos, char = next_char(context)
    assert char == "\\"

    pos, char = next_char(context)
    if char in escapable_chars:
        return char
    else:
        pushback_chars(context, (pos, char))
        return "\\"


# regexreplace ::= '/' text '/' text '/' [a-z]*
def _parse_decorated(context: ParserCtx[Local]) -> TokenStream:
    pos, char = next_char(context)
    assert char == "/"

    decoration_acc: List[str] = [char]
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
                        yield Unparsed(text=decoration)
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


# tabstop      ::= '$' int | '${' int '}'
# placeholder  ::= '${' int ':' ('#:'? any | regexreplace) '}'
def _parse_tp(context: ParserCtx[Local]) -> TokenStream:
    idx_acc: List[str] = []

    for pos, char in context:
        if char in _int_chars:
            idx_acc.append(char)
        else:
            yield Begin(idx=int("".join(idx_acc)))
            if char == "}":
                # tabstop     ::= '$' int | '${' int '}'
                yield End()
                break
            elif char == ":":
                context.local.depth += 1
                (p1, c1), (p2, c2) = next_char(context), next_char(context)
                # placeholder  ::= '${' int ':' ('#:'? any | regexreplace) '}'
                if c1 == "#" and c2 == ":":
                    pass
                else:
                    pushback_chars(context, (p1, c1), (p2, c2))
                break
            elif char == "/":
                pushback_chars(context, (pos, char))
                yield from _parse_decorated(context)
                yield End()
                break
            else:
                raise_err(
                    text=context.text,
                    pos=pos,
                    condition="after '${' int",
                    expected=("}", ":"),
                    actual=char,
                )


def _variable_substitution(context: ParserCtx[Local], *, name: str) -> Optional[str]:
    ctx = context.ctx
    if name == "VISUAL":
        return ""
    else:
        return None


def _consume_var_subst(context: ParserCtx[Local]) -> None:
    context.local.depth += 1
    for token in _parse(context, discard=True):
        pass


# variable    ::= '${' var '}' | '${' var ':' any '}'
def _parse_variable(context: ParserCtx[Local]) -> TokenStream:
    name_acc: List[str] = []

    for pos, char in context:
        if char == "}":
            name = "".join(name_acc)
            var = _variable_substitution(context, name=name)
            yield var if var is not None else name
            break
        elif char == ":":
            name = "".join(name_acc)
            var = _variable_substitution(context, name=name)
            if var is not None:
                yield var
                _consume_var_subst(context)
            else:
                yield DummyBegin()
                context.local.depth += 1
            break
        else:
            name_acc.append(char)


# ${...}
def _parse_inner_scope(context: ParserCtx[Local]) -> TokenStream:
    pos, char = next_char(context)
    assert char == "{"

    pos, char = next_char(context)
    if char in _int_chars:
        # tabstop | placeholder
        pushback_chars(context, (pos, char))
        yield from _parse_tp(context)
    elif char in _var_begin_chars:
        # variable
        pushback_chars(context, (pos, char))
        yield from _parse_variable(context)
    else:
        raise_err(
            text=context.text,
            pos=pos,
            condition="after ${",
            expected=("0-9", "A-z", "$"),
            actual=char,
        )


# $...
def _parse_scope(context: ParserCtx[Local]) -> TokenStream:
    pos, char = next_char(context)
    assert char == "$"

    pos, char = next_char(context)
    if char == "{":
        pushback_chars(context, (pos, char))
        yield from _parse_inner_scope(context)
    elif char in _int_chars:
        idx_acc: List[str] = [char]
        # tabstop     ::= '$' int
        for pos, char in context:
            if char in _int_chars:
                idx_acc.append(char)
            else:
                yield Begin(idx=int("".join(idx_acc)))
                yield End()
                pushback_chars(context, (pos, char))
                break
    else:
        pushback_chars(context, (pos, char))


# lang         ::= '`' text  '`' | '`!' [a-z] text '`'
def _parse_lang(context: ParserCtx[Local]) -> Token:
    pos, char = next_char(context)
    assert char == "`"

    acc: List[str] = []
    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            esc = _parse_escape(context, escapable_chars=_escapable_chars)
            acc.append(esc)
        elif char == "`":
            return Unparsed(text="".join(acc))
        else:
            acc.append(char)

    raise_err(context.text, pos=pos, condition="after `", expected=("`",), actual="")


# any          ::= tabstop | variable | placeholder | text
def _parse(context: ParserCtx[Local], discard: bool) -> TokenStream:
    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            yield _parse_escape(context, escapable_chars=_escapable_chars)
        elif context.local.depth and char == "}":
            yield End()
            context.local.depth -= 1
            if discard:
                break
        elif char == "$":
            pushback_chars(context, (pos, char))
            yield from _parse_scope(context)
        elif char == "`":
            pushback_chars(context, (pos, char))
            yield _parse_lang(context)
        else:
            yield char


def parser(context: Context, snippet: str) -> Parsed:
    local = Local(depth=0)
    ctx = context_from(snippet, context=context, local=local)
    tokens = _parse(ctx, discard=False)
    parsed = token_parser(ctx, stream=tokens)
    return parsed

