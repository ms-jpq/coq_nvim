from itertools import accumulate, chain, repeat
from os import linesep
from pprint import pformat
from typing import AbstractSet, Iterable, Iterator, Sequence, Tuple

from pynvim_pp.logging import log

from ..consts import DEBUG
from ..shared.parse import is_word
from ..shared.trans import expand_tabs, trans_adjusted
from ..shared.types import UTF8, Context, ContextualEdit, Edit, Mark, SnippetEdit
from .parsers.lsp import parser as lsp_parser
from .parsers.snu import parser as snu_parser
from .parsers.types import ParseInfo, Region


def _indent(ctx: Context, old_prefix: str, line_before: str) -> str:
    l = len(line_before.encode(UTF8)) - len(old_prefix.encode(UTF8))
    spaces = " " * ctx.tabstop
    return " " * l if ctx.expandtab else (" " * l).replace(spaces, "\t")


def _before_after(
    unifying_chars: AbstractSet[str], context: Context, text: str
) -> Tuple[str, str]:
    edit = Edit(new_text=text)
    c_edit = trans_adjusted(unifying_chars, ctx=context, edit=edit)
    return c_edit.old_prefix, c_edit.old_suffix


def _marks(
    ctx: Context,
    edit: ContextualEdit,
    regions: Iterable[Region],
) -> Iterator[Mark]:
    row, _ = ctx.position
    parsed_lines = edit.new_text.split(ctx.linefeed)
    old_lines = edit.old_prefix.split(ctx.linefeed)
    len8 = tuple(
        zip(
            accumulate(len(line.encode(UTF8)) + 1 for line in parsed_lines),
            parsed_lines,
        )
    )

    y_shift = row - len(old_lines) + 1

    for region in regions:
        r1, c1, r2, c2 = None, None, None, None
        last_len = 0

        for idx, (l8, _) in enumerate(len8):
            if r1 is None and l8 >= region.begin:
                r1, c1 = idx + y_shift, region.begin - last_len
            if r2 is None and l8 >= region.end:
                r2, c2 = idx + y_shift, region.end - last_len

            last_len = l8

        assert (r1 is not None and c1 is not None) and (
            r2 is not None and c2 is not None
        )
        begin = r1, c1
        end = r2, c2
        mark = Mark(idx=region.idx, begin=begin, end=end, text=region.text)
        yield mark


def parse(
    unifying_chars: AbstractSet[str],
    context: Context,
    snippet: SnippetEdit,
    sort_by: str,
    visual: str,
) -> Tuple[ContextualEdit, Sequence[Mark]]:
    parser = lsp_parser if snippet.grammar == "lsp" else snu_parser

    trigger_word = (
        context.words_before
        if is_word(sort_by[:1], unifying_chars=unifying_chars)
        else context.syms_before + context.words_before
    )
    indent = _indent(context, old_prefix=trigger_word, line_before=context.line_before)
    expanded_text = expand_tabs(context, text=snippet.new_text)
    indented_text = context.linefeed.join(
        lhs + rhs
        for lhs, rhs in zip(chain(("",), repeat(indent)), expanded_text.splitlines())
    )
    parsed = parser(context, snippet=indented_text, info=ParseInfo(visual=visual))

    old_prefix, old_suffix = _before_after(
        unifying_chars, context=context, text=parsed.text
    )

    edit = ContextualEdit(
        new_text=parsed.text,
        old_prefix=old_prefix,
        old_suffix=old_suffix,
        new_prefix=parsed.text[: parsed.cursor],
    )
    marks = tuple(_marks(context, edit=edit, regions=parsed.regions))

    if DEBUG:
        msg = pformat((snippet, parsed, edit, marks))
        log.debug("%s", msg)

    return edit, marks

