from os import linesep
from string import Template
from textwrap import dedent
from typing import Iterable, Iterator, MutableSequence, NoReturn, Tuple, TypeVar, Union

from std2.itertools import deiter
from std2.types import never

from ...shared.types import Context
from .types import (
    Begin,
    DummyBegin,
    EChar,
    End,
    Index,
    Parsed,
    ParseError,
    ParserCtx,
    Region,
    Token,
    TokenStream,
    Unparsed,
)

T = TypeVar("T")


def raise_err(
    text: str, pos: Index, condition: str, expected: Iterable[str], actual: str
) -> NoReturn:
    band = 5
    char = f"'{actual}'" if actual else "EOF"
    expected_chars = ", ".join(map(lambda c: f"'{c}'", expected))
    ctx = "" if pos.i == -1 else text[pos.i - band : pos.i + band + 1]
    tpl = """
    Unexpected char found @ ${condition}:
    row:  ${row}
    col:  ${col}
    Expected one of: ${expected_chars}
    Found:           ${char}
    Context: |-
    ${ctx}
    Text:    |-
    ${text}
    """
    msg = Template(dedent(tpl)).substitute(
        condition=condition,
        row=pos.row,
        col=pos.col,
        expected_chars=expected_chars,
        char=char,
        ctx=ctx,
        text=text,
    )
    raise ParseError(msg)


def next_char(context: ParserCtx) -> EChar:
    return next(context, (Index(i=-1, row=-1, col=-1), ""))


def pushback_chars(context: ParserCtx, *vals: EChar) -> None:
    for pos, char in reversed(vals):
        if char:
            context.dit.push_back((pos, char))


def _gen_iter(src: str) -> Iterator[EChar]:
    row, col = 1, 1
    for i, c in enumerate(src):
        yield Index(i=i, row=row, col=col), c
        col += 1
        if c == linesep:
            row += 1
            col = 0


def context_from(snippet: str, context: Context, local: T) -> ParserCtx[T]:
    dit = deiter(_gen_iter(snippet))
    ctx = ParserCtx(ctx=context, dit=dit, text=snippet, local=local)
    return ctx


def token_parser(context: ParserCtx, stream: TokenStream) -> Parsed:
    idx = 0
    regions: MutableSequence[Region] = []
    slices: MutableSequence[str] = []
    begins: MutableSequence[Tuple[int, Union[Begin, DummyBegin]]] = []
    bad_tokens: MutableSequence[Tuple[int, Token]] = []

    for token in stream:
        if isinstance(token, Unparsed):
            token = token
            bad_tokens.append((idx, token))
        elif isinstance(token, str):
            idx += len(token)
            slices.append(token)
        elif isinstance(token, Begin):
            begins.append((idx, token))
        elif isinstance(token, DummyBegin):
            begins.append((idx, token))
        elif isinstance(token, End):
            if begins:
                pos, begin = begins.pop()
                if isinstance(begin, Begin):
                    region = Region(idx=begin.idx, begin=pos, end=idx)
                    regions.append(region)
            else:
                bad_tokens.append((idx, token))
        else:
            never(token)

    bad_tokens.extend(begins)
    text = "".join(slices)
    cursor = min(region.idx for region in regions) if regions else 0
    if bad_tokens:
        tpl = """
        Bad tokens - ${bad_tokens}
        Parsed: |-
        ${text}
        Original: |-
        ${ctx}
        """
        msg = Template(dedent(tpl)).substitute(
            bad_tokens=bad_tokens, text=text, ctx=context.text
        )
        raise ParseError(msg)

    parsed = Parsed(text=text, cursor=cursor, regions=regions)
    return parsed

