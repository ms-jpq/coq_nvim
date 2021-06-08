from asyncio.events import Handle, get_running_loop
from typing import Any, Mapping, Optional, TypedDict

from pynvim.api.nvim import Nvim

from ...registry import autocmd, enqueue_event, rpc
from ..runtime import Stack


class _CompEvent(TypedDict, total=False):
    user_data: Any


@rpc(blocking=True)
def _dir_changed(nvim: Nvim, stack: Stack, event: Mapping[str, Any]) -> None:
    cwd: str = event["cwd"]
    stack.state.cwd = cwd


autocmd("DirChanged") << f"lua {_dir_changed.name}(vim.v.event)"


@rpc(blocking=True)
def _insert_enter(nvim: Nvim, stack: Stack) -> None:
    stack.state.inserting = True


autocmd("InsertEnter") << f"lua {_insert_enter.name}()"


@rpc(blocking=True)
def _insert_leave(nvim: Nvim, stack: Stack) -> None:
    stack.state.inserting = False


autocmd("InsertLeave") << f"lua {_insert_leave.name}()"


@rpc(blocking=True)
def _comp_done_pre(nvim: Nvim, stack: Stack, event: _CompEvent) -> None:
    data = event.get("user_data")
    if data:
        print(data, flush=True)


autocmd("CompleteDonePre") << f"lua {_comp_done_pre.name}(vim.v.completed_item)"


@rpc(blocking=True)
def _vaccum(nvim: Nvim, stack: Stack) -> None:
    stack.db.vaccum()


_handle: Optional[Handle] = None


@rpc(blocking=True)
def _cursor_hold(nvim: Nvim, stack: Stack) -> None:
    global _handle
    if _handle:
        _handle.cancel()

    def cont() -> None:
        enqueue_event(_vaccum)

    loop = get_running_loop()
    _handle = loop.call_later(0.5, cont)


autocmd("CursorHold", "CursorHoldI") << f"lua {_cursor_hold.name}()"
