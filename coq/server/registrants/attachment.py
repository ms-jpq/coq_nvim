from asyncio import gather
from asyncio.tasks import create_task
from contextlib import suppress
from time import monotonic
from typing import Mapping, Optional, Sequence, Tuple, cast
from uuid import uuid4

from pynvim_pp.atomic import Atomic
from pynvim_pp.buffer import Buffer
from pynvim_pp.logging import suppress_and_log
from pynvim_pp.nvim import Nvim
from pynvim_pp.rpc_types import NvimError
from pynvim_pp.types import NoneType
from pynvim_pp.window import Window
from std2.asyncio import Cancellation

from ...clients.buffers.worker import Worker as BufWorker
from ...registry import NAMESPACE, atomic, autocmd, rpc
from ...shared.timeit import timeit
from ...shared.types import ChangeEvent
from ..rt_types import Stack
from ..state import state
from .omnifunc import comp_func

_die = Cancellation()


@rpc()
async def _buf_enter(stack: Stack) -> None:
    state(commit_id=uuid4())
    win = await Window.get_current()
    buf = await win.get_buf()
    listed = await buf.opts.get(bool, "buflisted")
    buf_type = await buf.opts.get(str, "buftype")

    if listed and buf_type != "terminal":
        if await Nvim.api.buf_attach(bool, buf, False, {}):
            for worker in stack.workers:
                if isinstance(worker, BufWorker):
                    filetype = await buf.filetype()
                    filename = await buf.get_name() or ""
                    row, _ = await win.get_cursor()
                    height = await win.get_height()
                    line_count = await buf.line_count()
                    lo = max(0, row - height)
                    hi = min(line_count, row + height + 1)
                    lines = await buf.get_lines(lo=lo, hi=hi)
                    await worker.set_lines(
                        buf.number,
                        filetype=filetype,
                        filename=filename,
                        lo=lo,
                        hi=hi,
                        lines=lines,
                    )
                    break


_ = autocmd("BufEnter", "InsertEnter") << f"lua {NAMESPACE}.{_buf_enter.method}()"
atomic.exec_lua(f"{NAMESPACE}.{_buf_enter.method}()", ())


async def _status() -> Tuple[str, str]:
    with Atomic() as (atomic, ns):
        ns.mode = atomic.get_mode()
        ns.complete_info = atomic.call_function("complete_info", (("mode",),))
        await atomic.commit(NoneType)

    mode = cast(Mapping[str, str], ns.mode(NoneType))["mode"]
    comp_mode = cast(Mapping[str, str], ns.complete_info(NoneType))["mode"]

    return mode, comp_mode


@rpc(name="nvim_buf_lines_event")
async def _lines_event(
    stack: Stack,
    _: Buffer,
    change_tick: Optional[int],
    lo: int,
    hi: int,
    lines: Sequence[str],
    pending: bool,
) -> None:
    if change_tick is not None:
        t0 = monotonic()

        @_die
        async def cont() -> None:
            with suppress_and_log():
                with timeit("POLL"), suppress(NvimError):
                    (mode, comp_mode), _ = await gather(
                        _status(), stack.supervisor.interrupt()
                    )

                    s = state(change_id=uuid4())

                    if (
                        stack.settings.completion.always
                        and not pending
                        and mode.startswith("i")
                        and comp_mode in {"", "eval", "function", "ctrl_x"}
                    ):
                        change = ChangeEvent(range=range(lo, hi), lines=lines)
                        await comp_func(
                            stack=stack, s=s, change=change, t0=t0, manual=False
                        )

        create_task(cont())
