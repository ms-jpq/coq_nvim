from contextlib import suppress
from datetime import datetime
from pathlib import PurePath
from posixpath import normcase
from random import choices
from re import RegexFlag, compile
from re import error as RegexError
from string import ascii_letters, digits, hexdigits
from typing import (
    AbstractSet,
    Callable,
    Iterator,
    MutableSequence,
    Optional,
    Pattern,
    Sequence,
    Tuple,
)
from uuid import uuid4

from std2.functools import identity
from std2.lex import ParseError as StdLexError
from std2.lex import split
from std2.string import removeprefix, removesuffix

from ...shared.parse import lower
from ...shared.types import Context
from .lexer import context_from, next_char, pushback_chars, raise_err, token_parser
from .types import (
    EChar,
    End,
    Index,
    IntBegin,
    Parsed,
    ParseInfo,
    ParserCtx,
    TokenStream,
    Transform,
    VarBegin,
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


_ESC_CHARS = {"\\", "$", "}"}
_REGEX_ESC_CHARS = {"\\", "/"}
_CHOICE_ESC_CHARS = _ESC_CHARS | {",", "|"}
_INT_CHARS = {*digits}
_VAR_BEGIN_CHARS = {*ascii_letters}
_VAR_CHARS = {*digits, *ascii_letters, "_"}
_RE_FLAGS = {
    "i": RegexFlag.IGNORECASE,
    "m": RegexFlag.MULTILINE,
    "s": RegexFlag.DOTALL,
}
_REGEX_FLAG_CHARS = {*_RE_FLAGS, "g", "u"}


def _lex_escape(context: ParserCtx, *, escapable_chars: AbstractSet[str]) -> str:
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


def _choice_trans(choice: Optional[str]) -> Sequence[str]:
    sep, text = "|", removesuffix(removeprefix((choice or ""), prefix="["), suffix="]")
    with suppress(StdLexError):
        return tuple(split(text, sep=sep, esc="\\"))
    return text.split(sep)


# choice      ::= '${' int '|' text (',' text)* '|}'
def _half_lex_choice(context: ParserCtx, idx: int) -> TokenStream:
    pos, char = next_char(context)
    assert char == "|"

    yield "["
    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            for char in _lex_escape(context, escapable_chars=_CHOICE_ESC_CHARS):
                if char in {"\\", "|"}:
                    yield "\\"
                yield char
        elif char == "|":
            pos, char = next_char(context)
            if char == "}":
                yield "]"
                yield Transform(var_subst=None, maybe_idx=idx, xform=_choice_trans)
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
def _lex_tcp(context: ParserCtx) -> TokenStream:
    idx_acc: MutableSequence[str] = []

    for pos, char in context:
        if char in _INT_CHARS:
            idx_acc.append(char)
        else:
            idx = int("".join(idx_acc))
            yield IntBegin(idx=idx)
            if char == "}":
                # tabstop     ::= '$' int | '${' int '}'
                yield End()
                break
            elif char == "|":
                # choice      ::= '${' int '|' text (',' text)* '|}'
                pushback_chars(context, (pos, char))
                yield from _half_lex_choice(context, idx=idx)
                break
            elif char == ":":
                # placeholder ::= '${' int ':' any '}'
                context.stack.append(idx)
                break
            else:
                raise_err(
                    text=context.text,
                    pos=pos,
                    condition="while parsing (tabstop | choice | placeholder)",
                    expected=("0-9", "|", ":"),
                    actual=char,
                )


def _variable_substitution(context: ParserCtx, *, var_name: str) -> Optional[str]:
    ctx = context.ctx
    row, _ = ctx.position
    c_lhs, c_rhs = context.info.comment_str
    path = PurePath(ctx.filename)

    if var_name == "TM_SELECTED_TEXT":
        return context.info.visual

    elif var_name == "TM_CURRENT_LINE":
        return ctx.line

    elif var_name == "TM_CURRENT_WORD":
        return ctx.words

    elif var_name == "TM_LINE_INDEX":
        return str(row)

    elif var_name == "TM_LINE_NUMBER":
        return str(row + 1)

    elif var_name == "TM_FILENAME":
        return path.name

    elif var_name == "TM_FILENAME_BASE":
        return path.stem

    elif var_name == "TM_DIRECTORY":
        return normcase(path.parent)

    elif var_name == "TM_FILEPATH":
        return normcase(path)

    elif var_name == "RELATIVE_FILEPATH":
        try:
            return normcase(path.relative_to(ctx.cwd))
        except ValueError:
            return None

    elif var_name == "CLIPBOARD":
        return context.info.clipboard

    elif var_name == "WORKSPACE_NAME":
        return ctx.cwd.name

    elif var_name == "WORKSPACE_FOLDER":
        return normcase(ctx.cwd)

    # Randomv value related
    elif var_name == "RANDOM":
        return "".join(choices(digits, k=6))

    elif var_name == "RANDOM_HEX":
        return "".join(choices(tuple({*hexdigits.upper()}), k=6))

    elif var_name == "UUID":
        return str(uuid4())

    # Date/time related
    elif var_name == "CURRENT_YEAR":
        return datetime.now().strftime("%Y")

    elif var_name == "CURRENT_YEAR_SHORT":
        return datetime.now().strftime("%y")

    elif var_name == "CURRENT_MONTH":
        return datetime.now().strftime("%m")

    elif var_name == "CURRENT_MONTH_NAME":
        return datetime.now().strftime("%B")

    elif var_name == "CURRENT_MONTH_NAME_SHORT":
        return datetime.now().strftime("%b")

    elif var_name == "CURRENT_DATE":
        return datetime.now().strftime("%d")

    elif var_name == "CURRENT_DAY_NAME":
        return datetime.now().strftime("%A")

    elif var_name == "CURRENT_DAY_NAME_SHORT":
        return datetime.now().strftime("%a")

    elif var_name == "CURRENT_HOUR":
        return datetime.now().strftime("%H")

    elif var_name == "CURRENT_MINUTE":
        return datetime.now().strftime("%M")

    elif var_name == "CURRENT_SECOND":
        return datetime.now().strftime("%S")

    elif var_name == "CURRENT_SECONDS_UNIX":
        return str(round(datetime.now().timestamp()))

    elif var_name == "BLOCK_COMMENT_START":
        return c_lhs if c_lhs and c_rhs else None

    elif var_name == "BLOCK_COMMENT_END":
        return c_rhs if c_lhs and c_rhs else None

    elif var_name == "LINE_COMMENT":
        return (c_lhs or None) if not c_rhs else None

    else:
        return None


# variable    ::= '$' var
def _lex_variable_naked(context: ParserCtx) -> TokenStream:
    name_acc: MutableSequence[str] = []

    for pos, char in context:
        if char in _VAR_CHARS:
            name_acc.append(char)
        else:
            name = "".join(name_acc)
            var = _variable_substitution(context, var_name=name)
            yield var if var is not None else name
            pushback_chars(context, (pos, char))
            break


# regex
def _lex_regex(context: ParserCtx) -> Iterator[EChar]:
    _, char = next_char(context)
    assert char == "/"

    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            char = _lex_escape(context, escapable_chars=_REGEX_ESC_CHARS)
            yield pos, char

        elif char == "/":
            pushback_chars(context, (pos, char))
            break

        else:
            yield pos, char


# options
def _lex_options(context: ParserCtx) -> RegexFlag:
    pos, char = next_char(context)
    assert char == "/"

    flag = 0
    for pos, char in context:
        if char in _REGEX_FLAG_CHARS:
            flag |= _RE_FLAGS.get(char, 0)

        elif char == "}":
            break

        else:
            raise_err(
                text=context.text,
                pos=pos,
                condition="while parsing regex flags",
                expected=_REGEX_FLAG_CHARS,
                actual=char,
            )

    ref = RegexFlag(flag)
    return ref


# ':' '/upcase' | '/downcase' | '/capitalize' '}'
# ':+' if '}'
# ':?' if ':' else '}'
# ':-' else '}' | '${' int ':' else '}'
def _lex_fmt_back(context: ParserCtx) -> Callable[[str], str]:
    pos, char = next_char(context)
    assert char == ":"

    def cont(stop: str, init: Optional[str]) -> Iterator[str]:
        if init:
            yield init
        for pos, char in context:
            if char == "\\":
                pushback_chars(context, (pos, char))
                _ = _lex_escape(context, escapable_chars=_REGEX_ESC_CHARS)
            elif char == stop:
                break
            else:
                yield char

    pos, char = next_char(context)
    if char == "/":
        action = "".join(tuple(cont("}", init=None)))

        def trans(var: str) -> str:
            if action == "downcase":
                return lower(var)

            elif action == "upcase":
                return var.upper()

            elif action == "capitalize":
                return lower(var).capitalize()

            else:
                return var

    elif char == "+":
        replace = "".join(tuple(cont("}", init=None)))

        def trans(var: str) -> str:
            return replace if not var else var

    elif char == "?":
        replace_a = "".join(tuple(cont(":", init=None)))
        replace_b = "".join(tuple(cont("}", init=None)))

        def trans(var: str) -> str:
            return replace_a if var else replace_b

    elif char == "-":
        replace = "".join(tuple(cont(":", init=None)))

        def trans(var: str) -> str:
            return var if var else replace

    else:
        replace = "".join(tuple(cont(":", init=None)))

        def trans(var: str) -> str:
            return var if var else replace

    pos, char = next_char(context)
    if char == "/":
        pushback_chars(context, (pos, char))
        return trans
    else:
        raise_err(
            text=context.text,
            pos=pos,
            condition="after }",
            expected=("/",),
            actual=char,
        )


# format      ::= '$' int | '${' int '}'
#                 | '${' int ':' '/upcase' | '/downcase' | '/capitalize' '}'
#                 | '${' int ':+' if '}'
#                 | '${' int ':?' if ':' else '}'
#                 | '${' int ':-' else '}' | '${' int ':' else '}'
def _lex_fmt(context: ParserCtx) -> Tuple[int, Callable[[str], str]]:
    pos, char = next_char(context)
    assert char == "/"

    pos, char = next_char(context)
    if char != "$":
        raise_err(
            text=context.text,
            pos=pos,
            condition="while parsing format",
            expected=("$",),
            actual=char,
        )

    else:
        pos, char = next_char(context)
        # '$' int
        if char in _INT_CHARS:
            idx_acc = [char]
            for pos, char in context:
                if char in _INT_CHARS:
                    idx_acc.append(char)
                elif char == "/":
                    pushback_chars(context, (pos, char))
                    break
                else:
                    raise_err(
                        text=context.text,
                        pos=pos,
                        condition="while parsing format",
                        expected=("[0-9]",),
                        actual=char,
                    )
            group = int("".join(idx_acc))
            return group, identity

        # ${ int
        elif char == "{":
            idx_acc = []
            for pos, char in context:
                if char in _INT_CHARS:
                    idx_acc.append(char)

                # '${' int '}'
                elif char == "}":
                    group = int("".join(idx_acc)) if idx_acc else 0
                    return group, identity

                # ...
                elif char == ":":
                    pushback_chars(context, (pos, char))
                    group = int("".join(idx_acc)) if idx_acc else 0
                    trans = _lex_fmt_back(context)
                    return group, trans

                else:
                    raise_err(
                        text=context.text,
                        pos=pos,
                        condition="while parsing format",
                        expected=("[0-9]", ":"),
                        actual=char,
                    )
            else:
                raise_err(
                    text=context.text,
                    pos=pos,
                    condition="after ${'int'",
                    expected=("}", ":"),
                    actual=char,
                )

        else:
            raise_err(
                text=context.text,
                pos=pos,
                condition="while parsing format",
                expected=("[0-9]", "$"),
                actual=char,
            )


def _compile(
    context: ParserCtx,
    *,
    origin: Index,
    regex: Sequence[EChar],
    flag: RegexFlag,
) -> Pattern[str]:
    re = "".join(c for _, c in regex)
    try:
        return compile(re, flags=flag)
    except RegexError as e:
        if regex:
            (head_idx, _), *_ = regex
        else:
            head_idx = origin
        positions = {i: pos for i, (pos, _) in enumerate(regex)}
        pos = positions.get(e.pos, head_idx) if e.pos is not None else head_idx
        raise_err(
            text=context.text,
            pos=pos,
            condition=f"while compiling regex -- {re}",
            expected=(),
            actual=str(e),
        )


# | '${' var '/' regex '/' (format | text)+ '/' options '}'
def _lex_variable_decorated(context: ParserCtx, var_name: str) -> TokenStream:
    pos, char = next_char(context)
    assert char == "/"

    pushback_chars(context, (pos, char))
    regex = tuple(_lex_regex(context))
    group, trans = _lex_fmt(context)
    flag = _lex_options(context)

    sub = _variable_substitution(context, var_name=var_name)
    re = _compile(context, origin=pos, regex=regex, flag=flag)
    subst = var_name if sub is None else sub

    def xform(val: Optional[str]) -> str:
        text = val or subst
        if match := re.match(text):
            with suppress(IndexError):
                matched = match.group(group)
                return trans(matched)
        return trans(subst)

    yield (var_subst := xform(None))
    for idx in reversed(context.stack):
        if isinstance(idx, int):
            yield Transform(var_subst=var_subst, maybe_idx=idx, xform=xform)
            break


# variable    ::= '$' var | '${' var }'
#                | '${' var ':' any '}'
#                | '${' var '/' regex '/' (format | text)+ '/' options '}'
def _lex_variable_nested(context: ParserCtx) -> TokenStream:
    name_acc: MutableSequence[str] = []

    for pos, char in context:
        if char in _VAR_CHARS:
            name_acc.append(char)

        elif char == "}":
            # '${' var }'
            name = "".join(name_acc)
            var = _variable_substitution(context, var_name=name)
            yield var if var is not None else name
            break

        elif char == ":":
            # '${' var ':' any '}'
            name = "".join(name_acc)
            var = _variable_substitution(context, var_name=name)
            if var is not None:
                yield var
                context.stack.append(name)
                yield from _lex(context, shallow=True)
            else:
                yield VarBegin(name=name)
                context.stack.append(name)
            break

        elif char == "/":
            # '${' var '/' regex '/' (format | text)+ '/' options '}'
            name = "".join(name_acc)
            pushback_chars(context, (pos, char))
            yield from _lex_variable_decorated(context, var_name=name)
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
def _lex_inner_scope(context: ParserCtx) -> TokenStream:
    pos, char = next_char(context)
    assert char == "{"

    pos, char = next_char(context)
    if char in _INT_CHARS:
        # tabstop | placeholder | choice
        pushback_chars(context, (pos, char))
        yield from _lex_tcp(context)
    elif char in _VAR_BEGIN_CHARS:
        # variable
        pushback_chars(context, (pos, char))
        yield from _lex_variable_nested(context)
    else:
        raise_err(
            text=context.text,
            pos=pos,
            condition="after ${",
            expected=("_", "0-9", "A-z"),
            actual=char,
        )


# $...
def _lex_scope(context: ParserCtx) -> TokenStream:
    pos, char = next_char(context)
    assert char == "$"

    pos, char = next_char(context)
    if char == "{":
        pushback_chars(context, (pos, char))
        yield from _lex_inner_scope(context)
    elif char in _INT_CHARS:
        idx_acc = [char]
        # tabstop     ::= '$' int
        for pos, char in context:
            if char in _INT_CHARS:
                idx_acc.append(char)
            else:
                yield IntBegin(idx=int("".join(idx_acc)))
                yield End()
                pushback_chars(context, (pos, char))
                break
        else:
            yield IntBegin(idx=int("".join(idx_acc)))
            yield End()
    elif char in _VAR_BEGIN_CHARS:
        pushback_chars(context, (pos, char))
        yield from _lex_variable_naked(context)
    else:
        raise_err(
            text=context.text,
            pos=pos,
            condition="after $",
            expected=("{",),
            actual=char,
        )


# any         ::= tabstop | placeholder | choice | variable | text
def _lex(context: ParserCtx, shallow: bool) -> TokenStream:
    for pos, char in context:
        if char == "\\":
            pushback_chars(context, (pos, char))
            yield _lex_escape(context, escapable_chars=_ESC_CHARS)
        elif context.stack and char == "}":
            yield End()
            context.stack.pop()
            if shallow:
                break
        elif char == "$":
            pushback_chars(context, (pos, char))
            yield from _lex_scope(context)
        else:
            yield char


def tokenizer(context: Context, info: ParseInfo, snippet: str) -> Parsed:
    ctx = context_from(snippet, context=context, info=info)
    tokens = _lex(ctx, shallow=False)
    parsed = token_parser(ctx, stream=tokens)
    return parsed
