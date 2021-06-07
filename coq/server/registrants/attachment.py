from pynvim import Nvim
from pynvim.api import Buffer
from pynvim_pp.lib import write

from ...registry import rpc
from ..state import State


@rpc(blocking=True, alias="nvim_buf_lines_event")
def lines_event(nvim: Nvim, state: State, buf: Buffer) -> None:
    pass


@rpc(blocking=True, alias="nvim_buf_changedtick_event")
def buf_changedtick_event(nvim: Nvim, state: State, buf: Buffer) -> None:
    if state.insertion_mode:
        pass
    write(nvim, "nvim_buf_changedtick_event", _)


@rpc(blocking=True, alias="nvim_buf_detach_event")
def buf_detach_event(nvim: Nvim, state: State, buf: Buffer) -> None:
    pass
