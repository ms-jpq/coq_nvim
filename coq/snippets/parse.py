from dataclasses import dataclass
from itertools import accumulate
from pprint import pformat
from typing import Callable, Iterable, Iterator, Sequence, Tuple

from pynvim_pp.lib import encode
from std2.string import removesuffix
from std2.types import never

from ..shared.settings import CompleteOptions, MatchOptions
from ..shared.trans import indent_adjusted, trans_adjusted
from ..shared.types import (
    BaseRangeEdit,
    Context,
    ContextualEdit,
    Edit,
    Mark,
    NvimPos,
    SnippetEdit,
    SnippetGrammar,
    SnippetRangeEdit,
)
from .consts import SNIP_LINE_SEP
from .parsers.lsp import tokenizer as lsp_tokenizer
from .parsers.snu import tokenizer as snu_tokenizer
from .parsers.types import Parsed, ParseInfo, Region


@dataclass(frozen=True)
class ParsedEdit(BaseRangeEdit):
    new_prefix: str


_NL = len(encode(SNIP_LINE_SEP))


def _marks(
    pos: NvimPos,
    l0_before: str,
    new_lines: Sequence[str],
    regions: Iterable[Tuple[int, Region]],
) -> Sequence[Mark]:
    def cont() -> Iterator[Mark]:
        row, _ = pos
        len8 = tuple(accumulate(len(encode(line)) + _NL for line in new_lines))

        for r_idx, region in regions:
            r1, c1, r2, c2 = None, None, None, None
            last_len = 0

            for idx, l8 in enumerate(len8):
                x_shift = 0 if idx else len(encode(l0_before))

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

            begin, end = (r1, c1), (r2, c2)
            mark = Mark(idx=r_idx, begin=begin, end=end, text=region.text)
            yield mark

    return tuple(cont())


def _parser(grammar: SnippetGrammar) -> Callable[[Context, ParseInfo, str], Parsed]:
    if grammar is SnippetGrammar.lit:
        return lambda _, __, text: Parsed(text=text, cursor=len(text), regions=())
    elif grammar is SnippetGrammar.lsp:
        return lsp_tokenizer
    elif grammar is SnippetGrammar.snu:
        return snu_tokenizer
    else:
        never(grammar)


def parse_ranged(
    context: Context,
    adjust_indent: bool,
    snippet: SnippetRangeEdit,
    info: ParseInfo,
    line_before: str,
) -> Tuple[Edit, Sequence[Mark]]:
    parser = _parser(snippet.grammar)
    indented = (
        SNIP_LINE_SEP.join(
            indent_adjusted(
                context, line_before=line_before, lines=snippet.new_text.splitlines()
            )
        )
        if adjust_indent
        else snippet.new_text
    )

    parsed = parser(context, info, indented)
    new_prefix = parsed.text[: parsed.cursor]
    new_lines = parsed.text.split(SNIP_LINE_SEP)
    new_text = context.linefeed.join(new_lines)

    edit = ParsedEdit(
        new_text=new_text,
        begin=snippet.begin,
        end=snippet.end,
        cursor_pos=snippet.cursor_pos,
        encoding=snippet.encoding,
        new_prefix=new_prefix,
    )

    marks = _marks(
        context.position,
        l0_before=line_before,
        new_lines=new_lines,
        regions=parsed.regions,
    )
    return edit, marks


def parse_basic(
    match: MatchOptions,
    comp: CompleteOptions,
    adjust_indent: bool,
    context: Context,
    snippet: SnippetEdit,
    info: ParseInfo,
) -> Tuple[Edit, Sequence[Mark]]:
    parser = _parser(snippet.grammar)

    sort_by = parser(context, info, snippet.new_text).text
    trans_ctx = trans_adjusted(match, comp=comp, ctx=context, new_text=sort_by)
    old_prefix, old_suffix = trans_ctx.old_prefix, trans_ctx.old_suffix

    line_before = removesuffix(context.line_before, suffix=old_prefix)
    indented = (
        SNIP_LINE_SEP.join(
            indent_adjusted(
                context, line_before=line_before, lines=snippet.new_text.splitlines()
            )
        )
        if adjust_indent
        else snippet.new_text
    )

    parsed = parser(context, info, indented)
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
        l0_before=line_before,
        new_lines=new_lines,
        regions=parsed.regions,
    )
    return edit, marks
