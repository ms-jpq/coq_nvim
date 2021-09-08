from dataclasses import dataclass
from itertools import accumulate, chain, repeat
from pprint import pformat
from typing import AbstractSet, Iterable, Iterator, Sequence, Tuple

from pynvim_pp.logging import log
from std2.types import never

from ..consts import DEBUG
from ..shared.parse import is_word
from ..shared.trans import expand_tabs
from ..shared.types import (
    UTF8,
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
from .parsers.types import ParseInfo, Region


@dataclass(frozen=True)
class ParsedEdit(RangeEdit):
    new_prefix: str


def _indent(ctx: Context, old_prefix: str, line_before: str) -> Tuple[int, str]:
    l = len(line_before.encode(UTF8)) - len(old_prefix.encode(UTF8))
    spaces = " " * ctx.tabstop
    return l, " " * l if ctx.expandtab else (" " * l).replace(spaces, "\t")


def _marks(
    position: NvimPos,
    indent_len: int,
    edit: Edit,
    regions: Iterable[Tuple[int, Region]],
) -> Iterator[Mark]:
    row, _ = position
    l0_before = indent_len
    len8 = tuple(
        accumulate(len(line.encode(UTF8)) for line in edit.new_text.splitlines(True))
    )

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
        ), pformat((region, edit.new_text))
        begin = r1, c1
        end = r2, c2
        mark = Mark(idx=r_idx, begin=begin, end=end, text=region.text)
        yield mark


def parse(
    unifying_chars: AbstractSet[str],
    context: Context,
    snippet: SnippetEdit,
    visual: str,
) -> Tuple[Edit, Sequence[Mark]]:
    if snippet.grammar is SnippetGrammar.lsp:
        parser = lsp_parser
    elif snippet.grammar is SnippetGrammar.snu:
        parser = snu_parser
    else:
        never(snippet.grammar)

    sort_by = parser(
        context, snippet=snippet.new_text, info=ParseInfo(visual=visual)
    ).text

    old_prefix = (
        context.words_before
        if is_word(sort_by[:1], unifying_chars=unifying_chars)
        else context.syms_before
    )
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
    parsed = parser(context, snippet=indented_text, info=ParseInfo(visual=visual))
    old_suffix = (
        context.words_after
        if is_word(parsed.text[-1:], unifying_chars=unifying_chars)
        else ""
    )

    new_prefix = parsed.text.encode(UTF8)[: parsed.cursor].decode()
    new_text = context.linefeed.join(new_prefix.splitlines())

    if isinstance(snippet, SnippetRangeEdit):
        edit: Edit = ParsedEdit(
            new_text=new_text,
            begin=snippet.begin,
            end=snippet.end,
            encoding=snippet.encoding,
            new_prefix=new_prefix,
        )
    else:
        edit = ContextualEdit(
            new_text=new_text,
            old_prefix=old_prefix,
            old_suffix=old_suffix,
            new_prefix=new_prefix,
        )

    marks = tuple(
        _marks(
            context.position,
            indent_len=indent_len,
            edit=edit,
            regions=parsed.regions,
        )
    )

    if DEBUG:
        msg = pformat((snippet, parsed, edit, marks))
        log.debug("%s", msg)

    return edit, marks
