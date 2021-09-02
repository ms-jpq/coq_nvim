from json import dumps
from locale import strxfrm
from os import linesep
from os.path import normcase
from pathlib import PurePath
from string import Template
from typing import Iterable, Iterator

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_get_lines, buf_line_count, buf_name, cur_win, win_get_buf
from pynvim_pp.hold import hold_win_pos
from pynvim_pp.lib import write
from pynvim_pp.operators import operator_marks
from pynvim_pp.preview import set_preview
from std2.itertools import group_by

from ...registry import rpc
from ...shared.context import EMPTY_CONTEXT
from ...shared.types import SnippetEdit
from ...snippets.consts import MOD_PAD
from ...snippets.loaders.neosnippet import parse as parse_neosnippets
from ...snippets.parse import parse
from ...snippets.parsers.types import ParseError
from ...snippets.types import LoadError, ParsedSnippet
from ..rt_types import Stack

_SNIP = """
---

#### `${matches}`

```${syntax}
${body}
```

```json
${marks}
```

---
"""
_SNIP_T = Template(_SNIP)


def _trans(
    stack: Stack, path: PurePath, snips: Iterable[ParsedSnippet]
) -> Iterator[str]:
    for snip in snips:
        edit = SnippetEdit(grammar="lsp", new_text=snip.content)
        matches = dumps(
            sorted(snip.matches, key=strxfrm), check_circular=False, ensure_ascii=False
        )
        parsed, marks = parse(
            stack.settings.match.unifying_chars,
            context=EMPTY_CONTEXT,
            snippet=edit,
            visual="",
        )
        ms = group_by(marks, key=lambda m: m.idx % MOD_PAD, val=lambda m: m.text)
        yield _SNIP_T.substitute(
            syntax=path.stem,
            matches=matches,
            body=parsed.new_text,
            marks=ms,
        )


@rpc(blocking=True)
def eval_snips(nvim: Nvim, stack: Stack, visual: bool) -> None:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    line_count = buf_line_count(nvim, buf=buf)
    path = PurePath(normcase(buf_name(nvim, buf=buf)))

    if visual:
        (lo, _), (hi, _) = operator_marks(nvim, buf=buf, visual_type=None)
        hi = min(line_count, hi + 1)
    else:
        lo, hi = 0, line_count

    lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)

    try:
        _, snips = parse_neosnippets(path, lines=enumerate(lines, start=lo + 1))
    except LoadError as e:
        preview = str(e).splitlines()
        with hold_win_pos(nvim, win=win):
            set_preview(nvim, syntax="", preview=preview)
        write(nvim, "snip load fail")
    else:

        try:
            parsed = linesep.join(s for s in _trans(stack, path=path, snips=snips))
        except ParseError as e:
            preview = str(e).splitlines()

            with hold_win_pos(nvim, win=win):
                set_preview(nvim, syntax="", preview=preview)
            write(nvim, "snip parse fail")
        else:
            preview = str(parsed).splitlines()
            with hold_win_pos(nvim, win=win):
                set_preview(nvim, syntax="markdown", preview=preview)
            write(nvim, "snip parse succ")
