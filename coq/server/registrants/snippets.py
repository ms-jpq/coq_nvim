from os import linesep

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_get_lines, buf_line_count, cur_buf
from pynvim_pp.lib import write
from pynvim_pp.operators import operator_marks
from pynvim_pp.preview import set_preview

from ...registry import rpc
from ...shared.types import SnippetEdit
from ...snippets.parse import parse
from ...snippets.parsers.types import ParseError
from ..context import context
from ..rt_types import Stack
from ..state import state


@rpc(blocking=True)
def eval_snips(nvim: Nvim, stack: Stack, visual: bool) -> None:
    buf = cur_buf(nvim)
    line_count = buf_line_count(nvim, buf=buf)

    if visual:
        (lo, _), (hi, _) = operator_marks(nvim, buf=buf, visual_type=None)
        hi = min(line_count, hi)
    else:
        lo, hi = 0, line_count

    ctx = context(
        nvim,
        db=stack.bdb,
        options=stack.settings.match,
        state=state(),
        manual=True,
    )
    lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)
    snip = SnippetEdit(grammar="lsp", new_text=linesep.join(lines))
    try:
        parsed = parse(
            stack.settings.match.unifying_chars,
            context=ctx,
            snippet=snip,
            visual="",
        )
    except ParseError as e:
        preview = str(e).splitlines()
        set_preview(nvim, syntax="", preview=preview)
        write(nvim, "snip parse fail")
    else:
        preview = str(parsed).splitlines()
        set_preview(nvim, syntax="", preview=preview)
        write(nvim, "snip parse succ")
