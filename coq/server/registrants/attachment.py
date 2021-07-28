from contextlib import suppress
from queue import SimpleQueue
from typing import Sequence, Tuple
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import buf_filetype, buf_get_option, cur_buf
from pynvim_pp.lib import async_call, awrite, go
from std2.asyncio import run_in_executor

from ...lang import LANG
from ...registry import atomic, autocmd, rpc
from ..rt_types import Stack
from ..state import state
from .omnifunc import comp_func


@rpc(blocking=True)
def _buf_enter(nvim: Nvim, stack: Stack) -> None:
    state(commit_id=uuid4())
    with suppress(NvimError):
        buf = cur_buf(nvim)
        listed = buf_get_option(nvim, buf=buf, key="buflisted")
        buf_type: str = buf_get_option(nvim, buf=buf, key="buftype")
        if listed and buf_type != "terminal":
            nvim.api.buf_attach(buf, True, {})


autocmd("BufEnter", "InsertEnter") << f"lua {_buf_enter.name}()"

q: SimpleQueue = SimpleQueue()

_Qmsg = Tuple[str, bool, Buffer, Tuple[int, int], Sequence[str], str]


@rpc(blocking=True)
def _listener(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        while True:
            thing: _Qmsg = await run_in_executor(q.get)
            mode, pending, buf, (lo, hi), lines, ft = thing

            size = sum(map(len, lines))
            heavy_bufs = (
                {buf.number} if size > stack.settings.limits.max_buf_index else set()
            )
            s = state(change_id=uuid4(), heavy_bufs=heavy_bufs)

            if buf.number not in s.heavy_bufs:
                await stack.bdb.set_lines(
                    buf.number,
                    filetype=ft,
                    lo=lo,
                    hi=hi,
                    lines=lines,
                    unifying_chars=stack.settings.match.unifying_chars,
                )
            else:
                msg = LANG(
                    "buf 2 fat",
                    size=size,
                    limit=stack.settings.limits.max_buf_index,
                )
                await awrite(nvim, msg)

            if not pending and mode.startswith("i"):
                await async_call(nvim, comp_func, nvim, stack=stack, s=s, manual=False)

    go(nvim, aw=cont())


atomic.exec_lua(f"{_listener.name}()", ())


def _lines_event(
    nvim: Nvim,
    stack: Stack,
    buf: Buffer,
    tick: int,
    lo: int,
    hi: int,
    lines: Sequence[str],
    pending: bool,
) -> None:
    go(nvim, aw=stack.supervisor.interrupt())
    filetype = buf_filetype(nvim, buf=buf)
    mode = nvim.api.get_mode()["mode"]
    q.put((mode, pending, buf, (lo, hi), lines, filetype))


def _changed_event(nvim: Nvim, stack: Stack, buf: Buffer, tick: int) -> None:
    pass


def _detach_event(nvim: Nvim, stack: Stack, buf: Buffer) -> None:
    pass


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
    "nvim_buf_changedtick_event": _changed_event,
    "nvim_buf_detach_event": _detach_event,
}

