from pynvim import Nvim
from pynvim.api import NvimError
from pynvim_pp.api import buf_get_option, cur_buf, list_bufs
from pynvim_pp.lib import write

from ...registry import atomic, autocmd, rpc
from ..state import State


@rpc(blocking=True)
def _lines_event(nvim: Nvim, state: State, buf_nr: int) -> None:
    write(nvim, buf_nr)


_lua = f"""
(function (buf)
    local on_lines = function (_, buf, changedtick, lo, hi, wut)
        {_lines_event.name}(buf)
    end
    local go = vim.api.nvim_buf_attach(bur, True, {{on_lines = on_lines}})
    assert(go)
end)(...)
"""

_seen = {0}


@rpc(blocking=True)
def _buf_new(nvim: Nvim, state: State) -> None:
    buf = cur_buf(nvim)
    if buf.number in _seen:
        pass
    else:
        _seen.add(buf.number)
        try:
            listed = buf_get_option(nvim, buf=buf, key="buflisted")
            if listed:
                nvim.api.exec_lua(_lua, (buf.number,))
        except NvimError:
            pass


autocmd("BufNew") << f"lua {_buf_new.name}()"


@rpc(blocking=True)
def _buf_new_init(nvim: Nvim, state: State) -> None:
    for buf in list_bufs(nvim, listed=True):
        _seen.add(buf.number)
        nvim.api.exec_lua(_lua, (buf.number,))


atomic.exec_lua(f"{_buf_new_init.name}()", ())
