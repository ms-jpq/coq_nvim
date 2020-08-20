from os import linesep
from typing import Iterable
from uuid import uuid4

from pynvim import Nvim

from ...shared.nvim import call


async def autocmd(
    nvim: Nvim,
    *,
    name: str,
    events: Iterable[str],
    filters: Iterable[str] = ("*",),
    modifiers: Iterable[str] = (),
    arg_eval: Iterable[str] = (),
) -> None:
    _events = ",".join(events)
    _filters = " ".join(filters)
    _modifiers = " ".join(modifiers)
    _args = ", ".join(arg_eval)
    group = f"augroup {uuid4().hex}"
    cls = "autocmd!"
    cmd = (
        f"autocmd {_events} {_filters} {_modifiers} call _NARCnotify('{name}', {_args})"
    )
    group_end = "augroup END"

    def cont() -> None:
        commands = linesep.join((group, cls, cmd, group_end))
        nvim.api.exec(commands, False)

    await call(nvim, cont)
