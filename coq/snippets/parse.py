from itertools import accumulate, chain, repeat
from typing import Iterator, Sequence, Tuple

from ..shared.trans import trans
from ..shared.types import (
    UTF8,
    Context,
    ContextualEdit,
    Edit,
    EditEnv,
    Mark,
    SnippetEdit,
)
from .parsers.lsp import parser as lsp_parser
from .parsers.snu import parser as snu_parser
from .parsers.types import Parsed


def _indent(env: EditEnv, old_prefix: str, line_before: str) -> str:
    l = len(line_before.encode(UTF8)) - len(old_prefix.encode(UTF8))
    spaces = " " * env.tabstop
    return " " * l if env.expandtab else (" " * l).replace(spaces, "\t")


def _before_after(context: Context, text: str) -> Tuple[str, str]:
    edit = Edit(new_text=text)
    c_edit = trans(context.line_before, context.line_after, edit=edit)
    return c_edit.old_prefix, c_edit.old_suffix


def _marks(
    env: EditEnv, row: int, edit: ContextualEdit, indent: str, parsed: Parsed
) -> Iterator[Mark]:
    len8 = tuple(
        accumulate(
            len(line.encode(UTF8)) + 1 for line in parsed.text.split(env.linefeed)
        )
    )
    y_shift = row - (len(edit.new_prefix.split(env.linefeed)) - 1)
    x_shift = len(indent)

    for region in parsed.regions:
        r1, c1, r2, c2 = -1, -1, -1, -1
        last_len = 0
        for idx, l8 in enumerate(len8):
            if r1 == -1 and l8 >= region.begin:
                r1, c1 = idx + y_shift, region.begin - last_len + x_shift
            if r2 == -1 and l8 >= region.end:
                r2, c2 = idx + y_shift, region.end - last_len + x_shift
            last_len = l8

        assert r1 >= 0 and r2 >= 0
        begin = r1, c1
        end = r2, c2
        mark = Mark(idx=region.idx, begin=begin, end=end)
        yield mark


def parse(
    context: Context, env: EditEnv, snippet: SnippetEdit, sort_by: str
) -> Tuple[ContextualEdit, Sequence[Mark]]:
    row, _ = context.position
    parser = lsp_parser if snippet.grammar == "lsp" else snu_parser

    text = (
        snippet.new_text.replace("\t", " " * env.tabstop)
        if env.expandtab
        else snippet.new_text.replace(" " * env.tabstop, "\t")
    )
    parsed = parser(context, snippet=text)

    old_prefix, old_suffix = _before_after(context, text=sort_by + parsed.text)
    indent = _indent(env, old_prefix=old_prefix, line_before=context.line_before)
    new_lines = tuple(
        lhs + rhs
        for lhs, rhs in zip(
            chain(("",), repeat(indent)), parsed.text.split(env.linefeed)
        )
    )

    edit = ContextualEdit(
        new_text=env.linefeed.join(new_lines),
        old_prefix=old_prefix,
        old_suffix=old_suffix,
        new_prefix=parsed.text[: parsed.cursor],
    )
    marks = tuple(_marks(env, row=row, edit=edit, indent=indent, parsed=parsed))
    return edit, marks

