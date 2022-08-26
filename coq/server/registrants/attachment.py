from asyncio import Task, gather
from contextlib import suppress
from typing import Mapping, Optional, Sequence, Tuple, cast
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import (
    buf_filetype,
    buf_get_lines,
    buf_get_option,
    buf_line_count,
    buf_name,
    cur_win,
    win_get_buf,
    win_get_cursor,
)
from pynvim_pp.atomic import Atomic
from pynvim_pp.lib import async_call, go
from std2.asyncio import cancel

from ...clients.buffers.worker import Worker as BufWorker
from ...registry import NAMESPACE, atomic, autocmd, rpc
from ...shared.timeit import timeit
from ..rt_types import Stack
from ..state import state
from .omnifunc import comp_func


@rpc(blocking=True)
def _buf_enter(nvim: Nvim, stack: Stack) -> None:
    state(commit_id=uuid4())
    with suppress(NvimError):
        win = cur_win(nvim)
        buf = win_get_buf(nvim, win=win)
        listed = buf_get_option(nvim, buf=buf, key="buflisted")
        buf_type: str = buf_get_option(nvim, buf=buf, key="buftype")

        if listed and buf_type != "terminal":
            if nvim.api.buf_attach(buf, False, {}):
                for worker in stack.workers:
                    if isinstance(worker, BufWorker):
                        filetype = buf_filetype(nvim, buf=buf)
                        filename = buf_name(nvim, buf=buf)
                        row, _ = win_get_cursor(nvim, win=win)
                        height: int = nvim.api.win_get_height(win)
                        line_count = buf_line_count(nvim, buf=buf)
                        lo = max(0, row - height)
                        hi = min(line_count, row + height + 1)
                        lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)
                        go(
                            nvim,
                            aw=worker.set_lines(
                                buf.number,
                                filetype=filetype,
                                filename=filename,
                                lo=lo,
                                hi=hi,
                                lines=lines,
                            ),
                        )


_ = autocmd("BufEnter", "InsertEnter") << f"lua {NAMESPACE}.{_buf_enter.name}()"
atomic.exec_lua(f"{NAMESPACE}.{_buf_enter.name}()", ())


async def _status(nvim: Nvim, buf: Buffer) -> Tuple[str, str, str, str]:
    def cont() -> Tuple[str, str, str, str]:
        with Atomic() as (atomic, ns):
            ns.filetype = atomic.buf_get_option(buf, "filetype")
            ns.mode = atomic.get_mode()
            ns.complete_info = atomic.call_function("complete_info", (("mode",),))
            ns.filename = atomic.buf_get_name(buf)
            atomic.commit(nvim)

        filetype = cast(str, ns.filetype)
        filename = cast(str, ns.filename)
        mode = cast(Mapping[str, str], ns.mode)["mode"]
        comp_mode = cast(Mapping[str, str], ns.complete_info)["mode"]

        return mode, comp_mode, filetype, filename

    return await async_call(nvim, cont)


_TASK: Optional[Task] = None


def _lines_event(
    nvim: Nvim,
    stack: Stack,
    buf: Buffer,
    change_tick: Optional[int],
    lo: int,
    hi: int,
    lines: Sequence[str],
    pending: bool,
) -> None:
    global _TASK

    task = _TASK

    async def cont() -> None:
        if task:
            await cancel(task)

        with timeit("POLL"), suppress(NvimError):
            (mode, comp_mode, filetype, filename), _ = await gather(
                _status(nvim, buf), stack.supervisor.interrupt()
            )

            s = state(change_id=uuid4())

            for worker in stack.workers:
                if isinstance(worker, BufWorker):
                    await worker.set_lines(
                        buf.number,
                        filetype=filetype,
                        filename=filename,
                        lo=lo,
                        hi=hi,
                        lines=lines,
                    )

            if (
                stack.settings.completion.always
                and not pending
                and mode.startswith("i")
                and comp_mode in {"", "eval", "function", "ctrl_x"}
            ):
                await comp_func(nvim, stack=stack, s=s, manual=False)

    if change_tick is not None:
        _TASK = cast(Task, go(nvim, aw=cont()))


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
}
