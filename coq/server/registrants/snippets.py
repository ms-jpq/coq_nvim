from dataclasses import dataclass
from locale import strxfrm
from pathlib import PurePath
from typing import Iterator, Mapping, Sequence

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_get_lines, buf_line_count, cur_win, win_get_buf
from pynvim_pp.hold import hold_win_pos
from pynvim_pp.lib import write
from pynvim_pp.operators import operator_marks
from pynvim_pp.preview import set_preview
from std2.itertools import group_by

from ...registry import rpc
from ...shared.types import SnippetEdit
from ...snippets.consts import MOD_PAD
from ...snippets.loaders.neosnippet import parse as parse_neosnippets
from ...snippets.parse import parse
from ...snippets.parsers.types import ParseError
from ...snippets.types import LoadError
from ..context import context
from ..rt_types import Stack
from ..state import state


@dataclass(frozen=True)
class _Snip:
    matches: Sequence[str]
    parsed: str
    marks: Mapping[int, Sequence[str]]


@rpc(blocking=True)
def eval_snips(nvim: Nvim, stack: Stack, visual: bool) -> None:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    line_count = buf_line_count(nvim, buf=buf)

    if visual:
        (lo, _), (hi, _) = operator_marks(nvim, buf=buf, visual_type=None)
        hi = min(line_count, hi + 1)
    else:
        lo, hi = 0, line_count

    ctx = context(
        nvim,
        db=stack.bdb,
        options=stack.settings.match,
        state=state(),
        manual=True,
    )
    path = PurePath(ctx.filename)
    lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)

    try:
        _, snips = parse_neosnippets(path, lines=enumerate(lines, start=lo + 1))
    except LoadError as e:
        preview = str(e).splitlines()
        with hold_win_pos(nvim, win=win):
            set_preview(nvim, syntax="", preview=preview)
        write(nvim, "snip load fail")
    else:

        def cont() -> Iterator[_Snip]:
            for snip in snips:
                edit = SnippetEdit(grammar="lsp", new_text=snip.content)
                parsed, marks = parse(
                    stack.settings.match.unifying_chars,
                    context=ctx,
                    snippet=edit,
                    visual="",
                )
                snippet = _Snip(
                    matches=sorted(snip.matches, key=strxfrm),
                    parsed=parsed.new_text,
                    marks=group_by(
                        marks,
                        key=lambda m: m.idx % MOD_PAD,
                        val=lambda m: m.text,
                    ),
                )
                yield snippet

        try:
            parsed = tuple(cont())
        except ParseError as e:
            preview = str(e).splitlines()

            with hold_win_pos(nvim, win=win):
                set_preview(nvim, syntax="", preview=preview)
            write(nvim, "snip parse fail")
        else:
            preview = str(parsed).splitlines()
            with hold_win_pos(nvim, win=win):
                set_preview(nvim, syntax="", preview=preview)
            write(nvim, "snip parse succ")
