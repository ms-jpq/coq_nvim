from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import buf_get_option, cur_buf, list_bufs
from pynvim_pp.lib import write

from ...registry import atomic, autocmd, rpc
from ..state import State

_SEEN = {0}


@rpc(blocking=True)
def _buf_new(nvim: Nvim, state: State) -> None:
    buf = cur_buf(nvim)
    if buf.number in _SEEN:
        pass
    else:
        _SEEN.add(buf.number)
        try:
            listed = buf_get_option(nvim, buf=buf, key="buflisted")
            if listed:
                succ = nvim.api.buf_attach(buf, True, {})
                assert succ
        except NvimError:
            pass


autocmd("BufNew") << f"lua {_buf_new.name}()"


@rpc(blocking=True)
def _buf_new_init(nvim: Nvim, state: State) -> None:
    for buf in list_bufs(nvim, listed=True):
        _SEEN.add(buf.number)
        succ = nvim.api.buf_attach(buf, True, {})
        assert succ


atomic.exec_lua(f"{_buf_new_init.name}()", ())


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
