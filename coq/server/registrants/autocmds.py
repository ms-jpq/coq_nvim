from pynvim import Nvim

from ...registry import autocmd, rpc
from ..state import State


@rpc(blocking=True)
def _dir_changed(nvim: Nvim, state: State, *_: None) -> None:
    cwd: str = nvim.api.nvim_get_vvar("event")["cwd"]
    state.cwd = cwd


autocmd("DirChanged") << f"lua {_dir_changed.name}()"


@rpc(blocking=True)
def _insert_enter(nvim: Nvim, state: State) -> None:
    state.inserting = True


autocmd("InsertEnter") << f"lua {_insert_enter.name}()"


@rpc(blocking=True)
def _insert_leave(nvim: Nvim, state: State) -> None:
    state.inserting = False


autocmd("InsertLeave") << f"lua {_insert_leave.name}()"


@rpc(blocking=True)
def _comp_done_pre(nvim: Nvim, state: State) -> None:
    pass


autocmd("CompleteDonePre") << f"lua {_comp_done_pre.name}()"
