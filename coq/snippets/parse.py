from dataclasses import dataclass
from itertools import accumulate, chain, repeat
from pprint import pformat
from typing import AbstractSet, Callable, Iterable, Iterator, Sequence, Tuple

from pynvim_pp.lib import encode
from std2.types import never

from ..shared.trans import expand_tabs, trans_adjusted
from ..shared.types import (
    Context,
    ContextualEdit,
    Edit,
    Mark,
    NvimPos,
    RangeEdit,
    SnippetEdit,
    SnippetGrammar,
    SnippetRangeEdit,
)
from .consts import SNIP_LINE_SEP
from .parsers.lsp import parser as lsp_parser
from .parsers.snu import parser as snu_parser
from .parsers.types import Parsed, ParseInfo, Region


@dataclass(frozen=True)
class ParsedEdit(RangeEdit):
    new_prefix: str


_NL = len(encode(SNIP_LINE_SEP))


def _indent(ctx: Context, old_prefix: str, line_before: str) -> Tuple[int, str]:
    indent_len = len(line_before) - len(old_prefix)
    indent_blen = len(encode(line_before)) - len(encode(old_prefix))
    indent = (
        " " * indent_len
        if ctx.expandtab
        else (" " * indent_len).replace(" " * ctx.tabstop, "\t")
    )
    return indent_blen, indent


def _marks(
    pos: NvimPos,
    indent_blen: int,
    new_lines: Sequence[str],
    regions: Iterable[Tuple[int, Region]],
) -> Sequence[Mark]:
    def cont() -> Iterator[Mark]:
        row, _ = pos
        l0_before = indent_blen
        len8 = tuple(accumulate(len(encode(line)) + _NL for line in new_lines))

        for r_idx, region in regions:
            r1, c1, r2, c2 = None, None, None, None
            last_len = 0

            for idx, l8 in enumerate(len8):
                x_shift = 0 if idx else l0_before
                if r1 is None:
                    if l8 > region.begin:
                        r1, c1 = idx + row, region.begin - last_len + x_shift
                    elif l8 == region.begin:
                        r1, c1 = idx + row + 1, x_shift

                if r2 is None:
                    if l8 > region.end:
                        r2, c2 = idx + row, region.end - last_len + x_shift
                    elif l8 == region.end:
                        r2, c2 = idx + row + 1, x_shift

                if r1 is not None and r2 is not None:
                    break

                last_len = l8

            assert (r1 is not None and c1 is not None) and (
                r2 is not None and c2 is not None
            ), pformat((region, new_lines))
            begin = r1, c1
            end = r2, c2
            mark = Mark(idx=r_idx, begin=begin, end=end, text=region.text)
            yield mark

    return tuple(cont())


def _parser(grammar: SnippetGrammar) -> Callable[[Context, ParseInfo, str], Parsed]:
    if grammar is SnippetGrammar.lsp:
        return lsp_parser
    elif grammar is SnippetGrammar.snu:
        return snu_parser
    else:
        never(grammar)


def parse_range(
    context: Context,
    snippet: SnippetRangeEdit,
    info: ParseInfo,
    line_before: str,
) -> Tuple[Edit, Sequence[Mark]]:
    parser = _parser(snippet.grammar)
    indent_blen = len(encode(line_before))
    expanded_text = expand_tabs(context, text=snippet.new_text)
    parsed = parser(context, info, expanded_text)

    new_prefix = parsed.text[: parsed.cursor]
    new_lines = parsed.text.split(SNIP_LINE_SEP)
    new_text = context.linefeed.join(new_lines)

    edit = ParsedEdit(
        new_text=new_text,
        begin=snippet.begin,
        end=snippet.end,
        encoding=snippet.encoding,
        new_prefix=new_prefix,
        fallback=snippet.fallback,
    )

    marks = _marks(
        context.position,
        indent_blen=indent_blen,
        new_lines=new_lines,
        regions=parsed.regions,
    )
    return edit, marks


def parse_norm(
    unifying_chars: AbstractSet[str],
    context: Context,
    snippet: SnippetEdit,
    info: ParseInfo,
) -> Tuple[Edit, Sequence[Mark]]:
    parser = _parser(snippet.grammar)

    sort_by = parser(context, info, snippet.new_text).text
    trans_ctx = trans_adjusted(unifying_chars, ctx=context, new_text=sort_by)
    old_prefix, old_suffix = trans_ctx.old_prefix, trans_ctx.old_suffix

    indent_len, indent = _indent(
        context, old_prefix=old_prefix, line_before=context.line_before
    )
    expanded_text = expand_tabs(context, text=snippet.new_text)
    indented_lines = tuple(
        lhs + rhs
        for lhs, rhs in zip(
            chain(("",), repeat(indent)), expanded_text.splitlines(True)
        )
    )
    indented_text = "".join(indented_lines)

    parsed = parser(context, info, indented_text)
    new_prefix = parsed.text[: parsed.cursor]
    new_lines = parsed.text.split(SNIP_LINE_SEP)
    new_text = context.linefeed.join(new_lines)

    edit = ContextualEdit(
        new_text=new_text,
        old_prefix=old_prefix,
        old_suffix=old_suffix,
        new_prefix=new_prefix,
    )

    marks = _marks(
        context.position,
        indent_blen=indent_len,
        new_lines=new_lines,
        regions=parsed.regions,
    )
    return edit, marks
