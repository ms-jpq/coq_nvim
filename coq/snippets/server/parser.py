from collections import deque
from os import linesep
from typing import Any, Iterable, Iterator, List, NoReturn, Tuple, TypeVar, Union, cast

from ..shared.types import Context
from .types import (
    Begin,
    DummyBegin,
    EChar,
    End,
    Index,
    ParseContext,
    Parsed,
    ParseError,
    Region,
    Token,
    TokenStream,
    Unparsable,
)

T = TypeVar("T")


def raise_err(
    text: str, pos: Index, condition: str, expected: Iterable[str], actual: str
) -> NoReturn:
    band = 5
    char = f"'{actual}'" if actual else "EOF"
    expected_chars = ", ".join(map(lambda c: f"'{c}'", expected))
    index = pos.i
    ctx = "" if index == -1 else f"{text[index-band:index+band+1]}"
    msg = f"""
Unexpected char found @ {condition}:
row:  {pos.row}
col:  {pos.col}
Expected one of: {expected_chars}
Found:           {char}
Context: |-
{ctx}
Text:    |-
{text}
    """
    raise ParseError(msg)


def gen_iter(src: str) -> Iterator[EChar]:
    row, col = 1, 1
    for i, c in enumerate(src):
        yield Index(i=i, row=row, col=col), c
        col += 1
        if c == linesep:
            row += 1
            col = 0


def context_from(snippet: str, context: Context, local: T) -> ParseContext[T]:
    queue = deque(gen_iter(snippet))
    ctx = ParseContext(vals=context, queue=queue, text=snippet, local=local)
    return ctx


def next_char(context: ParseContext) -> EChar:
    return next(context, (Index(i=-1, row=-1, col=-1), ""))


def pushback_chars(context: ParseContext, *vals: EChar) -> None:
    for pos, char in reversed(vals):
        if char:
            context.queue.appendleft((pos, char))


def log_rest(context: ParseContext) -> NoReturn:
    def cont() -> Iterator[str]:
        for _, char in context:
            yield char

    text = "".join(cont())
    raise ParseError(f"Rest: |-{linesep}{text}")


def token_parser(context: ParseContext, stream: TokenStream) -> Parsed:
    idx = 0
    regions: List[Region] = []
    slices: List[str] = []
    begins: List[Tuple[int, Union[Begin, DummyBegin]]] = []
    unparsables: List[Unparsable] = []
    bad_tokens: List[Tuple[int, Token]] = []

    for token in stream:
        if type(token) is Unparsable:
            token = cast(Unparsable, token)
            unparsables.append(token)
        elif type(token) is str:
            token = cast(str, token)
            idx += len(token)
            slices.append(token)
        elif type(token) is Begin:
            token = cast(Begin, token)
            begins.append((idx, token))
        elif type(token) is DummyBegin:
            token = cast(DummyBegin, token)
            begins.append((idx, token))
        elif type(token) is End:
            if begins:
                pos, begin = begins.pop()
                if type(begin) is Begin:
                    begin = cast(Begin, begin)
                    region = Region(idx=begin.idx, begin=pos, end=idx)
                    regions.append(region)
            else:
                bad_tokens.append((idx, token))
        else:
            assert False, f"unrecognized token: {token}"

    text = "".join(slices)
    cursor = min(region.idx for region in regions) if regions else 0
    if begins or bad_tokens:
        all_tokens = cast(List[Any], begins) + cast(List[Any], bad_tokens)
        msg = f"""
Unbalanced tokens - {all_tokens}
Parsed: |-
{text}
Original: |-
{context.text}
"""
        raise ParseError(msg)

    parsed = Parsed(text=text, cursor=cursor, regions=regions)
    return parsed
