from asyncio import Handle
from asyncio.events import AbstractEventLoop
from contextlib import suppress
from typing import Optional

from pynvim.api.nvim import Nvim, NvimError
from pynvim_pp.api import (
    buf_filetype,
    buf_get_option,
    buf_name,
    cur_buf,
    get_cwd,
    win_close,
)
from pynvim_pp.float_win import list_floatwins
from pynvim_pp.lib import async_call, awrite, go
from std2.locale import si_prefixed_smol

from ...clients.buffers.worker import Worker as BufWorker
from ...clients.tags.worker import Worker as TagsWorker
from ...clients.tmux.worker import Worker as TmuxWorker
from ...clients.tree_sitter.worker import Worker as TSWorker
from ...lang import LANG
from ...registry import NAMESPACE, atomic, autocmd, rpc
from ..rt_types import Stack
from ..state import state


@rpc(blocking=True)
def _kill_float_wins(nvim: Nvim, stack: Stack) -> None:
    wins = tuple(list_floatwins(nvim))
    if len(wins) != 2:
        for win in wins:
            win_close(nvim, win=win)


_ = autocmd("WinEnter") << f"lua {NAMESPACE}.{_kill_float_wins.name}()"


@rpc(blocking=True)
def _new_cwd(nvim: Nvim, stack: Stack) -> None:
    cwd = get_cwd(nvim)

    async def cont() -> None:
        s = state(cwd=cwd)
        for worker in stack.workers:
            if isinstance(worker, TagsWorker):
                await worker.swap(s.cwd)

    go(nvim, aw=cont())


_ = autocmd("DirChanged") << f"lua {NAMESPACE}.{_new_cwd.name}()"


@rpc(blocking=True)
def _ft_changed(nvim: Nvim, stack: Stack) -> None:

    for worker in stack.workers:
        if isinstance(worker, BufWorker):
            buf = cur_buf(nvim)
            ft = buf_filetype(nvim, buf=buf)
            filename = buf_name(nvim, buf=buf)
            go(nvim, aw=worker.buf_update(buf.number, filetype=ft, filename=filename))


_ = autocmd("FileType") << f"lua {NAMESPACE}.{_ft_changed.name}()"
atomic.exec_lua(f"{NAMESPACE}.{_ft_changed.name}()", ())


@rpc(blocking=True)
def _insert_enter(nvim: Nvim, stack: Stack) -> None:
    async def cont(worker: TSWorker) -> None:
        if populated := await worker.populate():
            keep_going, elapsed = populated

            if not keep_going:
                state(nono_bufs={buf.number})
                msg = LANG(
                    "source slow",
                    source=stack.settings.clients.tree_sitter.short_name,
                    elapsed=si_prefixed_smol(elapsed, precision=0),
                )
                await awrite(nvim, msg, error=True)

    for worker in stack.workers:
        if isinstance(worker, TSWorker):
            buf = cur_buf(nvim)
            nono_bufs = state().nono_bufs
            if buf.number not in nono_bufs:
                go(nvim, aw=cont(worker))


_ = autocmd("InsertEnter") << f"lua {NAMESPACE}.{_insert_enter.name}()"


@rpc(blocking=True)
def _on_focus(nvim: Nvim, stack: Stack) -> None:
    for worker in stack.workers:
        if isinstance(worker, TmuxWorker):
            go(nvim, aw=worker.periodical())


_ = autocmd("FocusGained") << f"lua {NAMESPACE}.{_on_focus.name}()"

_HANDLE: Optional[Handle] = None


@rpc(blocking=True)
def _when_idle(nvim: Nvim, stack: Stack) -> None:
    global _HANDLE
    if _HANDLE:
        _HANDLE.cancel()

    def cont() -> None:
        with suppress(NvimError):
            buf = cur_buf(nvim)
            buf_type: str = buf_get_option(nvim, buf=buf, key="buftype")
            if buf_type == "terminal":
                nvim.api.buf_detach(buf)
                state(nono_bufs={buf.number})

        _insert_enter(nvim, stack=stack)
        stack.supervisor.notify_idle()

    assert isinstance(nvim.loop, AbstractEventLoop)
    _HANDLE = nvim.loop.call_later(
        stack.settings.limits.idle_timeout,
        lambda: go(nvim, aw=async_call(nvim, cont)),
    )


_ = autocmd("CursorHold", "CursorHoldI") << f"lua {NAMESPACE}.{_when_idle.name}()"
