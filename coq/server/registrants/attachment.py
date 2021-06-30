from asyncio import AbstractEventLoop, TimerHandle
from contextlib import suppress
from typing import Optional, Sequence

from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import buf_filetype, buf_get_option, cur_buf, list_bufs

from ...registry import atomic, autocmd, enqueue_event, rpc
from ...shared.timeit import timeit
from ..rt_types import Stack
from .omnifunc import comp_func


@rpc(blocking=True)
def _buf_enter(nvim: Nvim, stack: Stack) -> None:
    with suppress(NvimError):
        buf = cur_buf(nvim)
        listed = buf_get_option(nvim, buf=buf, key="buflisted")
        buf_type: str = buf_get_option(nvim, buf=buf, key="buftype")
        if listed and buf_type != "terminal":
            nvim.api.buf_attach(buf, True, {})


autocmd("BufEnter", "InsertEnter") << f"lua {_buf_enter.name}()"


@rpc(blocking=True)
def _buf_new_init(nvim: Nvim, stack: Stack) -> None:
    with suppress(NvimError):
        for buf in list_bufs(nvim, listed=True):
            buf_type: str = buf_get_option(nvim, buf=buf, key="buftype")
            if buf_type != "terminal":
                nvim.api.buf_attach(buf, True, {})


atomic.exec_lua(f"{_buf_new_init.name}()", ())


_HANDLE: Optional[TimerHandle] = None
_LATER = 0.02


def _go(nvim: Nvim, stack: Stack) -> None:
    enqueue_event(comp_func, False)


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
    global _HANDLE

    filetype = buf_filetype(nvim, buf=buf)
    stack.bdb.set_lines(
        buf.number,
        filetype=filetype,
        lo=lo,
        hi=hi,
        lines=lines,
        unifying_chars=stack.settings.match.unifying_chars,
    )
    if not pending:
        if isinstance(nvim.loop, AbstractEventLoop):
            if _HANDLE:
                _HANDLE.cancel()
            _HANDLE = nvim.loop.call_later(_LATER, _go, nvim, stack)


def _changed_event(nvim: Nvim, stack: Stack, buf: Buffer, tick: int) -> None:
    pass


def _detach_event(nvim: Nvim, stack: Stack, buf: Buffer) -> None:
    pass


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
    "nvim_buf_changedtick_event": _changed_event,
    "nvim_buf_detach_event": _detach_event,
}

