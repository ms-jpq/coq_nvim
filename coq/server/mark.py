from typing import Sequence
from uuid import uuid4

from pynvim.api.common import NvimError
from pynvim.api.nvim import Buffer, Nvim
from pynvim_pp.lib import write
from pynvim_pp.logging import log

from ..lang import LANG
from ..shared.settings import Settings
from ..shared.types import Mark

NS = uuid4().hex


def mark(nvim: Nvim, settings: Settings, buf: Buffer, marks: Sequence[Mark]) -> None:
    mks = tuple(mark for mark in marks if mark.idx and mark.text)

    ns = nvim.api.create_namespace(NS)
    nvim.api.buf_clear_namespace(buf, ns, 0, -1)
    for mark in mks:
        (r1, c1), (r2, c2) = mark.begin, mark.end
        opts = {
            "id": mark.idx + 1,
            "end_line": r2,
            "end_col": c2,
            "hl_group": settings.display.mark_highlight_group,
        }
        try:
            nvim.api.buf_set_extmark(buf, ns, r1, c1, opts)
        except NvimError:
            log.warn("%s", f"bad mark location {mark}")

    msg = LANG("added marks", regions=" ".join(f"[{mark.text}]" for mark in mks))
    write(nvim, msg)
