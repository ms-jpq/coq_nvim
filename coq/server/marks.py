from typing import Iterable

from pynvim import Nvim
from pynvim.api import Buffer

from ..consts import NS
from ..shared.types import Mark


def mark(nvim: Nvim, buf: Buffer, marks: Iterable[Mark]) -> None:
    ns = nvim.api.create_namespace(NS)
    nvim.api.buf_clear_namespace(buf, ns, 0, -1)
    for mark in marks:
        (r1, c1), (r2, c2) = mark.begin, mark.end
        opts = {"end_line": r2, "end_col": c2, "hl_group": "Pmenu"}
        nvim.api.buf_set_extmark(buf, ns, r1, c1, opts)

