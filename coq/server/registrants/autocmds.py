from asyncio import Task, create_task, gather, sleep
from contextlib import suppress
from typing import Optional
from uuid import uuid4

from pynvim_pp.buffer import Buffer
from pynvim_pp.float_win import list_floatwins
from pynvim_pp.nvim import Nvim
from pynvim_pp.types import NoneType, NvimError
from std2.asyncio import cancel
from std2.cell import RefCell
from std2.locale import si_prefixed_smol

from ...clients.buffers.worker import Worker as BufWorker
from ...clients.registers.worker import Worker as RegWorker
from ...clients.tags.worker import Worker as TagsWorker
from ...clients.tmux.worker import Worker as TmuxWorker
from ...clients.tree_sitter.worker import Worker as TSWorker
from ...lang import LANG
from ...registry import NAMESPACE, atomic, autocmd, rpc
from ..rt_types import Stack
from ..state import state

_NS = uuid4()
_CELL = RefCell[Optional[Task]](None)


@rpc()
async def _kill_float_wins(stack: Stack) -> None:
    wins = [w async for w in list_floatwins(_NS)]
    if len(wins) != 2:
        for win in wins:
            await win.close()


_ = autocmd("WinEnter") << f"lua {NAMESPACE}.{_kill_float_wins.method}()"


@rpc()
async def _new_cwd(stack: Stack) -> None:
    cwd = await Nvim.getcwd()
    s = state(cwd=cwd)
    for worker in stack.workers:
        if isinstance(worker, TagsWorker):
            await worker.swap(s.cwd)
            break


_ = autocmd("DirChanged") << f"lua {NAMESPACE}.{_new_cwd.method}()"


@rpc()
async def _ft_changed(stack: Stack) -> None:
    for worker in stack.workers:
        if isinstance(worker, BufWorker):
            buf = await Buffer.get_current()
            ft = await buf.filetype()
            filename = await buf.get_name() or ""
            await worker.buf_update(buf.number, filetype=ft, filename=filename)
            break


_ = autocmd("FileType") << f"lua {NAMESPACE}.{_ft_changed.method}()"
atomic.exec_lua(f"{NAMESPACE}.{_ft_changed.method}()", ())


@rpc()
async def _insert_enter(stack: Stack) -> None:
    for worker in stack.workers:
        if isinstance(worker, TSWorker):
            buf = await Buffer.get_current()
            nono_bufs = state().nono_bufs
            if buf.number not in nono_bufs:
                if populated := await worker.populate():
                    keep_going, elapsed = populated

                    if not keep_going:
                        state(nono_bufs={buf.number})
                        msg = LANG(
                            "source slow",
                            source=stack.settings.clients.tree_sitter.short_name,
                            elapsed=si_prefixed_smol(elapsed, precision=0),
                        )
                        await Nvim.write(msg, error=True)
            break


@rpc()
async def _on_focus(stack: Stack) -> None:
    for worker in stack.workers:
        if isinstance(worker, TmuxWorker):
            await worker.periodical()
            break


_ = autocmd("FocusGained") << f"lua {NAMESPACE}.{_on_focus.method}()"


@rpc()
async def _when_idle(stack: Stack) -> None:
    if task := _CELL.val:
        _CELL.val = None
        await cancel(task)

    async def cont() -> None:
        await sleep(stack.settings.limits.idle_timeout)
        with suppress(NvimError):
            buf = await Buffer.get_current()
            buf_type = await buf.opts.get(str, "buftype")
            if buf_type == "terminal":
                await Nvim.api.buf_detach(NoneType, buf)
                state(nono_bufs={buf.number})

        await gather(_insert_enter(stack=stack), stack.supervisor.notify_idle())

    _CELL.val = create_task(cont())


_ = autocmd("CursorHold", "CursorHoldI") << f"lua {NAMESPACE}.{_when_idle.method}()"


@rpc()
async def _on_yank(stack: Stack, operator: str, regname: str) -> None:
    if operator == "y":
        for worker in stack.workers:
            if isinstance(worker, RegWorker):
                worker.post_yank(regname)


_LUA = f"""
(function()
  local acc = 0
  for _, line in pairs(vim.v.event.regcontents) do
    acc = acc + #line
    if acc >= 888 then
      return
    end
  end
  {NAMESPACE}.{_on_yank.method}(vim.v.event.operator, vim.v.event.regname)
end)()
"""

_ = autocmd("TextYankPost") << f"lua {_LUA}"
