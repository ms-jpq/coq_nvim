from itertools import accumulate, chain, repeat
from typing import Iterable, Iterator, Sequence, Tuple

from ..shared.types import UTF8, Context, ContextualEdit, EditEnv, Mark, SnippetEdit
from .parsers.lsp import parser as lsp_parser
from .parsers.snu import parser as snu_parser
from .parsers.types import Region


def _indent(env: EditEnv, line_before: str) -> str:
    spaces = " " * env.tabstop
    l = len(line_before.replace("\t", spaces))
    return " " * l if env.expandtab else (" " * l).replace(spaces, "\t")


def _marks(
    env: EditEnv,
    row: int,
    new_prefix: str,
    indent: str,
    new_lines: Iterable[str],
    regions: Iterable[Region],
) -> Iterator[Mark]:
    len8 = tuple(accumulate(len(line.encode(UTF8)) + 1 for line in new_lines))
    line_shift = row - (len(new_prefix.split(env.linefeed)) - 1)

    for region in regions:
        r1, c1, r2, c2 = -1, -1, -1, -1
        last_len = 0
        for idx, l8 in enumerate(len8):
            if r1 == -1 and l8 >= region.begin:
                r1, c1 = idx + line_shift, region.begin - last_len + len(indent)
            if r2 == -1 and l8 >= region.end:
                r2, c2 = idx + line_shift, region.end - last_len + len(indent)
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
    indent = _indent(env, line_before=context.line_before)
    new_lines = tuple(
        lhs + rhs
        for lhs, rhs in zip(
            chain((context.line_before,), repeat(indent)),
            parsed.text.split(env.linefeed),
        )
    )
    new_text = env.linefeed.join(new_lines)

    new_prefix = new_text[: parsed.cursor + len(indent)]
    edit = ContextualEdit(
        new_text=new_text,
        old_prefix=context.words_before,
        old_suffix=context.words_after,
        new_prefix=new_prefix,
    )
    marks = tuple(
        _marks(
            env,
            row=row,
            new_prefix=new_prefix,
            indent=indent,
            new_lines=new_lines,
            regions=parsed.regions,
        )
    )
    return edit, marks

