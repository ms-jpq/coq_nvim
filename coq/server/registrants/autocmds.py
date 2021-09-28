from asyncio import Handle, get_running_loop
from asyncio.tasks import gather
from typing import Optional

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_filetype, buf_get_option, cur_buf, get_cwd, win_close
from pynvim_pp.float_win import list_floatwins
from pynvim_pp.lib import async_call, awrite, go
from std2.locale import si_prefixed_smol

from ...lang import LANG
from ...registry import NAMESPACE, atomic, autocmd, rpc
from ...tmux.parse import snapshot
from ...treesitter.request import async_request
from ..rt_types import Stack
from ..state import state


@rpc(blocking=True)
def _kill_float_wins(nvim: Nvim, stack: Stack) -> None:
    wins = tuple(list_floatwins(nvim))
    if len(wins) != 2:
        for win in wins:
            win_close(nvim, win=win)


autocmd("WinEnter") << f"lua {NAMESPACE}.{_kill_float_wins.name}()"


@rpc(blocking=True)
def _new_cwd(nvim: Nvim, stack: Stack) -> None:
    cwd = get_cwd(nvim)

    async def cont() -> None:
        s = state(cwd=cwd)
        await stack.ctdb.swap(s.cwd)

    go(nvim, aw=cont())


autocmd("DirChanged") << f"lua {NAMESPACE}.{_new_cwd.name}()"


@rpc(blocking=True)
def _ft_changed(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    ft = buf_filetype(nvim, buf=buf)

    async def cont() -> None:
        await stack.bdb.ft_update(buf.number, filetype=ft)

    go(nvim, aw=cont())


autocmd("FileType") << f"lua {NAMESPACE}.{_ft_changed.name}()"
atomic.exec_lua(f"{NAMESPACE}.{_ft_changed.name}()", ())


@rpc(blocking=True)
def _insert_enter(nvim: Nvim, stack: Stack) -> None:
    ts = stack.settings.clients.tree_sitter
    nono_bufs = state().nono_bufs
    buf = cur_buf(nvim)

    async def c1() -> None:
        await stack.bdb.del_bufs(nono_bufs)

    async def c2() -> None:
        if ts.enabled:
            payloads, elapsed = (
                ((), 0)
                if buf.number in nono_bufs
                else await async_request(nvim, lines_around=ts.search_context)
            )
            await stack.tdb.new_nodes(payloads)
            if elapsed > ts.slow_threshold:
                state(nono_bufs={buf.number})
                msg = LANG(
                    "source slow",
                    source=ts.short_name,
                    elapsed=si_prefixed_smol(elapsed, precision=0),
                )
                await awrite(nvim, msg, error=True)

    go(nvim, aw=gather(c1(), c2()))


autocmd("InsertEnter") << f"lua {NAMESPACE}.{_insert_enter.name}()"


@rpc(blocking=True)
def _on_focus(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        snap = await snapshot(stack.settings.match.unifying_chars)
        await stack.tmdb.periodical(snap)

    go(nvim, aw=cont())


autocmd("FocusGained") << f"lua {NAMESPACE}.{_on_focus.name}()"

_HANDLE: Optional[Handle] = None


@rpc(blocking=True)
def _when_idle(nvim: Nvim, stack: Stack) -> None:
    global _HANDLE
    if _HANDLE:
        _HANDLE.cancel()

    def cont() -> None:
        buf = cur_buf(nvim)
        buf_type: str = buf_get_option(nvim, buf=buf, key="buftype")
        if buf_type == "terminal":
            nvim.api.buf_detach(buf)
            state(nono_bufs={buf.number})

        _insert_enter(nvim, stack=stack)
        stack.supervisor.notify_idle()

    get_running_loop().call_later(
        stack.settings.limits.idle_timeout,
        lambda: go(nvim, aw=async_call(nvim, cont)),
    )


autocmd("CursorHold", "CursorHoldI") << f"lua {NAMESPACE}.{_when_idle.name}()"
