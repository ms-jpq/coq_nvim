from os import linesep
from string import Template
from textwrap import dedent
from typing import (
    Iterable,
    Iterator,
    Mapping,
    MutableMapping,
    MutableSequence,
    NoReturn,
    Sequence,
    Tuple,
    TypeVar,
    Union,
)

from std2.itertools import deiter
from std2.types import never

from ...shared.types import UTF8, Context
from ..consts import LINKED_PAD
from .types import (
    Begin,
    DummyBegin,
    EChar,
    End,
    Index,
    Parsed,
    ParseError,
    ParseInfo,
    ParserCtx,
    ParserState,
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


def context_from(snippet: str, context: Context, info: ParseInfo) -> ParserCtx:
    dit = deiter(_gen_iter(snippet))
    state = ParserState(depth=0)
    ctx = ParserCtx(
        ctx=context,
        text=snippet,
        info=info,
        dit=dit,
        state=state,
    )
    return ctx


def _overlap(r1: Region, r2: Region) -> bool:
    return (r1.begin >= r2.begin and r1.end <= r2.end) or (
        r2.begin >= r1.begin and r2.end <= r1.end
    )


def _consolidate(
    text: str, regions: Mapping[int, Sequence[Region]]
) -> Iterator[Tuple[int, Region]]:
    new_regions = (
        (
            r.end - r.begin,
            idx,
            Region(begin=r.begin, end=r.end, text=text[r.begin : r.end]),
        )
        for idx, rs in regions.items()
        for r in rs
    )
    ordered = sorted(new_regions, key=lambda t: t[:-1])

    acc: MutableMapping[int, MutableSequence[Region]] = {}
    for _, idx, region in ordered:
        if not any(_overlap(region, r) for rs in acc.values() for r in rs):
            a = acc.setdefault(idx, [])
            a.append(region)

    for idx, rs in acc.items():
        for i, region in enumerate(rs, start=len(rs) > 1):
            yield idx + LINKED_PAD * i, region


def token_parser(context: ParserCtx, stream: TokenStream) -> Parsed:
    idx = 0
    raw_regions: MutableMapping[int, MutableSequence[Region]] = {}
    slices: MutableSequence[str] = []
    begins: MutableSequence[Tuple[int, Union[Begin, DummyBegin]]] = []
    bad_tokens: MutableSequence[Tuple[int, Token]] = []

    for token in stream:
        if isinstance(token, Unparsed):
            token = token
            bad_tokens.append((idx, token))
        elif isinstance(token, str):
            idx += len(token.encode(UTF8))
            slices.append(token)
        elif isinstance(token, Begin):
            begins.append((idx, token))
        elif isinstance(token, DummyBegin):
            begins.append((idx, token))
        elif isinstance(token, End):
            if begins:
                pos, begin = begins.pop()
                if isinstance(begin, Begin):
                    acc = raw_regions.setdefault(begin.idx, [])
                    acc.append(Region(begin=pos, end=idx, text=""))
            else:
                bad_tokens.append((idx, token))
        else:
            never(token)

    bad_tokens.extend(begins)
    text = "".join(slices)
    cursor = next(
        iter(raw_regions.get(0, ())),
        Region(begin=len(text.encode(UTF8)), end=0, text=""),
    ).begin

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

    regions = tuple(_consolidate(text, regions=raw_regions))
    parsed = Parsed(text=text, cursor=cursor, regions=regions)
    return parsed
