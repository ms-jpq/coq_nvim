from itertools import accumulate, chain, repeat
from typing import Iterable, Iterator, Sequence, Tuple

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


def _indent(env: EditEnv, line_before: str) -> str:
    spaces = " " * env.tabstop
    l = len(line_before.replace("\t", spaces))
    return " " * l if env.expandtab else (" " * l).replace(spaces, "\t")


def _before_after(context: Context, text: str) -> Tuple[str, str]:
    edit = Edit(new_text=text)
    c_edit = trans(context.line_before, context.line_after, edit=edit)
    return c_edit.old_prefix, c_edit.old_suffix


def _marks(
    env: EditEnv, row: int, new_prefix: str, indent: str, parsed: Parsed
) -> Iterator[Mark]:
    len8 = tuple(
        accumulate(len(indent) + len(line.encode(UTF8)) + 1 for line in parsed.text)
    )
    line_shift = row - (len(new_prefix.split(env.linefeed)) - 1)

    for region in parsed.regions:
        r1, c1, r2, c2 = -1, -1, -1, -1
        last_len = 0
        for idx, l8 in enumerate(len8):
            if r1 == -1 and l8 >= region.begin:
                r1, c1 = idx + line_shift, region.begin - last_len
            if r2 == -1 and l8 >= region.end:
                r2, c2 = idx + line_shift, region.end - last_len
            last_len = l8

        assert r1 >= 0 and r2 >= 0
        begin = r1, c1
        end = r2, c2
        mark = Mark(idx=region.idx, begin=begin, end=end)
        yield mark


def parse(
    context: Context, env: EditEnv, snippet: SnippetEdit
) -> Tuple[ContextualEdit, Sequence[Mark]]:
    row, _ = context.position
    parser = lsp_parser if snippet.grammar == "lsp" else snu_parser

    text = (
        snippet.new_text.replace("\t", " " * env.tabstop)
        if env.expandtab
        else snippet.new_text.replace(" " * env.tabstop, "\t")
    )
    parsed = parser(context, snippet=text)

    old_prefix, old_suffix = _before_after(context, text=parsed.text)
    indent = _indent(env, line_before=context.line_before)
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
    marks = tuple(
        _marks(env, row=row, new_prefix=edit.new_prefix, indent=indent, parsed=parsed)
    )
    return edit, marks

