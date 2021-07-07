from itertools import accumulate, chain, repeat
from pprint import pformat
from typing import AbstractSet, Iterator, Mapping, Sequence, Tuple

from pynvim_pp.logging import log

from ..consts import DEBUG
from ..shared.parse import is_word
from ..shared.trans import expand_tabs
from ..shared.types import UTF8, Context, ContextualEdit, Mark, SnippetEdit
from .parsers.lsp import parser as lsp_parser
from .parsers.snu import parser as snu_parser
from .parsers.types import ParseInfo, Region


def _indent(ctx: Context, old_prefix: str, line_before: str) -> Tuple[int, str]:
    l = len(line_before.encode(UTF8)) - len(old_prefix.encode(UTF8))
    spaces = " " * ctx.tabstop
    return l, " " * l if ctx.expandtab else (" " * l).replace(spaces, "\t")


def _marks(
    ctx: Context,
    indent_len: int,
    parsed_lines: Sequence[str],
    regions: Mapping[int, Region],
) -> Iterator[Mark]:
    row, _ = ctx.position
    l0_before = indent_len
    len8 = tuple(accumulate(len(line.encode(UTF8)) for line in parsed_lines))

    for r_idx, region in regions.items():
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
        ), pformat((region, parsed_lines))
        begin = r1, c1
        end = r2, c2
        mark = Mark(idx=r_idx, begin=begin, end=end, text=region.text)
        yield mark


def parse(
    unifying_chars: AbstractSet[str],
    context: Context,
    snippet: SnippetEdit,
    sort_by: str,
    visual: str,
) -> Tuple[ContextualEdit, Sequence[Mark]]:
    parser = lsp_parser if snippet.grammar == "lsp" else snu_parser

    old_prefix = (
        context.words_before
        if is_word(sort_by[:1], unifying_chars=unifying_chars)
        else context.syms_before + context.words_before
    )
    indent_len, indent = _indent(
        context, old_prefix=old_prefix, line_before=context.line_before
    )
    expanded_text = expand_tabs(context, text=snippet.new_text)
    indented_text = context.linefeed.join(
        lhs + rhs
        for lhs, rhs in zip(chain(("",), repeat(indent)), expanded_text.splitlines())
    )
    parsed = parser(context, snippet=indented_text, info=ParseInfo(visual=visual))
    old_suffix = (
        context.words_after
        if is_word(parsed.text[-1:], unifying_chars=unifying_chars)
        else context.words_after + context.syms_after
    )

    edit = ContextualEdit(
        new_text=parsed.text,
        old_prefix=old_prefix,
        old_suffix=old_suffix,
        new_prefix=parsed.text.encode(UTF8)[: parsed.cursor].decode(),
    )
    marks = tuple(
        _marks(
            context,
            indent_len=indent_len,
            parsed_lines=expanded_text.splitlines(keepends=True),
            regions=parsed.regions,
        )
    )

    if DEBUG:
        msg = pformat((snippet, parsed, edit, marks))
        log.debug("%s", msg)

    return edit, marks

