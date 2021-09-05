from typing import Sequence
from uuid import uuid4

from pynvim.api.common import NvimError
from pynvim.api.nvim import Buffer, Nvim
from pynvim_pp.api import ExtMark, buf_set_extmarks, clear_ns, create_ns
from pynvim_pp.lib import write
from pynvim_pp.logging import log

from ..lang import LANG
from ..shared.settings import Settings
from ..shared.types import Mark

NS = uuid4()


def mark(nvim: Nvim, settings: Settings, buf: Buffer, marks: Sequence[Mark]) -> None:
    emarks = tuple(
        ExtMark(
            idx=mark.idx + 1,
            begin=mark.begin,
            end=mark.end,
            meta={"hl_group": settings.display.mark_highlight_group},
        )
        for mark in marks
        if mark.idx or mark.text
    )
    ns = create_ns(nvim, ns=NS)
    clear_ns(nvim, buf=buf, id=ns)

    try:
        buf_set_extmarks(nvim, buf=buf, id=ns, marks=emarks)
    except NvimError:
        log.warn("%s", f"bad mark location {mark}")

    msg = LANG("added marks", regions=" ".join(f"[{mark.text}]" for mark in marks))
    write(nvim, msg)
