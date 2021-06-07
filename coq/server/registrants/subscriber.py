from pynvim import Nvim
from pynvim.api import NvimError
from pynvim_pp.api import buf_get_option, cur_buf

from ...registry import autocmd, rpc
from ..state import State


@rpc(blocking=True)
def _dir_changed(nvim: Nvim, state: State, *_: None) -> None:
    cwd: str = nvim.api.nvim_get_vvar("event")["cwd"]
    state.cwd = cwd


autocmd("DirChanged") << f"lua {_dir_changed.name}()"

_SEEN = {0}


@rpc(blocking=True)
def _buf_new(nvim: Nvim, *_: None) -> None:
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
def _insert_enter(nvim: Nvim, state: State, *_: None) -> None:
    state.insertion_mode = True


autocmd("InsertEnter") << f"lua {_insert_enter.name}()"


@rpc(blocking=True)
def _insert_leave(nvim: Nvim, state: State, *_: None) -> None:
    state.insertion_mode = False


autocmd("InsertLeave") << f"lua {_insert_leave.name}()"


@rpc(blocking=True)
def _comp_done_pre(nvim: Nvim, state: State, *_: None) -> None:
    pass


autocmd("CompleteDonePre") << f"lua {_comp_done_pre.name}()"
