from asyncio.events import Handle, get_running_loop
from typing import Optional

from pynvim.api.nvim import Nvim

from ...registry import autocmd, rpc
from ..runtime import Stack


@rpc(blocking=True)
def _dir_changed(nvim: Nvim, stack: Stack, *_: None) -> None:
    cwd: str = nvim.api.get_vvar("event")["cwd"]
    stack.state.cwd = cwd


autocmd("DirChanged") << f"lua {_dir_changed.name}()"


@rpc(blocking=True)
def _insert_enter(nvim: Nvim, stack: Stack) -> None:
    stack.state.inserting = True


autocmd("InsertEnter") << f"lua {_insert_enter.name}()"


@rpc(blocking=True)
def _insert_leave(nvim: Nvim, stack: Stack) -> None:
    stack.state.inserting = False


autocmd("InsertLeave") << f"lua {_insert_leave.name}()"


@rpc(blocking=True)
def _comp_done_pre(nvim: Nvim, stack: Stack) -> None:
    target = nvim.api.get_vvar("completed_item")
    print(target, flush=True)


autocmd("CompleteDonePre") << f"lua {_comp_done_pre.name}()"


_handle: Optional[Handle] = None


@rpc(blocking=True)
def _cursor_hold(nvim: Nvim, stack: Stack) -> None:
    global _handle
    if _handle:
        _handle.cancel()

    def cont() -> None:
        stack.db.vaccum()

    loop = get_running_loop()
    _handle = loop.call_later(0.5, cont)


autocmd("CursorHold", "CursorHoldI") << f"lua {_cursor_hold.name}()"
