from contextlib import suppress
from typing import Sequence
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import buf_filetype, buf_get_option, cur_buf
from pynvim_pp.lib import async_call, go, write

from ...registry import autocmd, rpc
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


@rpc(blocking=True)
def _launch(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        while True:
            pass

    go(nvim, aw=cont())


# atomic.exec_lua(f"{_launch.name}()", ())


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
    filetype = buf_filetype(nvim, buf=buf)
    mode = nvim.api.get_mode()["mode"]
    size = sum(map(len, lines))
    heavy_bufs = {buf.number} if size > stack.settings.limits.max_buf_index else set()
    s = state(change_id=uuid4(), heavy_bufs=heavy_bufs)

    async def cont() -> None:
        if not heavy_bufs:
            await stack.bdb.set_lines(
                buf.number,
                filetype=filetype,
                lo=lo,
                hi=hi,
                lines=lines,
                unifying_chars=stack.settings.match.unifying_chars,
            )
        else:
            msg = f"❌ 👉 :: {size} > {stack.settings.limits.max_buf_index}"
            write(nvim, msg, error=True)

        if not pending and mode.startswith("i"):
            await async_call(nvim, comp_func, nvim, stack=stack, s=s, manual=False)

    go(nvim, aw=cont())


def _changed_event(nvim: Nvim, stack: Stack, buf: Buffer, tick: int) -> None:
    pass


def _detach_event(nvim: Nvim, stack: Stack, buf: Buffer) -> None:
    pass


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
    "nvim_buf_changedtick_event": _changed_event,
    "nvim_buf_detach_event": _detach_event,
}

