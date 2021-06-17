from itertools import accumulate
from typing import Iterator, Sequence, Tuple

from ..shared.types import UTF8, Context, ContextualEdit, EditEnv, Mark, SnippetEdit
from .parsers.lsp import parser as lsp_parser
from .parsers.snu import parser as snu_parser
from .parsers.types import Parsed


def _marks(linefeed: str, new_prefix: str, row: int, parsed: Parsed) -> Iterator[Mark]:
    len8 = tuple(
        accumulate(len(line.encode(UTF8)) for line in parsed.text.split(linefeed))
    )
    line_shift = row - len(new_prefix) - 1

    for region in parsed.regions:
        r1, c1, r2, c2 = -1, -1, -1, -1
        last_len = 0
        for idx, l8 in enumerate(len8):
            if r1 != -1 and l8 > region.begin:
                r1, c1 = idx + line_shift, region.begin - last_len
            if r2 != -1 and l8 > region.end:
                r2, c2 = idx + line_shift, region.end - last_len
            last_len = l8

        assert r1 != -1 and r2 != -1
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
    new_prefix = parsed.text[: parsed.cursor]

    edit = ContextualEdit(
        new_text=parsed.text,
        old_prefix=context.words_before,
        old_suffix=context.words_after,
        new_prefix=new_prefix,
    )
    marks = tuple(_marks(env.linefeed, new_prefix=new_prefix, row=row, parsed=parsed))
    return edit, marks

