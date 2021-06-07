from typing import Sequence

from pynvim import Nvim
from pynvim.api import Buffer
from pynvim_pp.api import (
    buf_filetype,
    buf_get_option,
    buf_name,
    cur_buf,
    cur_win,
    list_bufs,
    win_get_cursor,
)

from ...registry import atomic, autocmd, rpc
from ..runtime import Stack
from .omnifunc import omnifunc


@rpc(blocking=True)
def _buf_new(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    listed = buf_get_option(nvim, buf=buf, key="buflisted")
    if listed:
        succ = nvim.api.buf_attach(buf, True, {})
        assert succ


autocmd("BufNew") << f"lua {_buf_new.name}()"


@rpc(blocking=True)
def _buf_new_init(nvim: Nvim, stack: Stack) -> None:
    for buf in list_bufs(nvim, listed=True):
        succ = nvim.api.buf_attach(buf, True, {})
        assert succ


atomic.exec_lua(f"{_buf_new_init.name}()", ())


def _lines_event(
    nvim: Nvim,
    stack: Stack,
    buf: Buffer,
    tick: int,
    lo: int,
    hi: int,
    lines: Sequence[str],
    multipart: bool,
) -> None:
    file = buf_name(nvim, buf=buf)
    filetype = buf_filetype(nvim, buf=buf)

    stack.db.set_lines(
        buf=buf.number,
        tick=tick,
        file=file,
        filetype=filetype,
        lo=lo,
        hi=hi,
        lines=lines,
        unifying_chars=stack.settings.match.unifying_chars,
    )

    if stack.state.inserting:
        omnifunc(nvim, stack)


def _changed_event(nvim: Nvim, stack: Stack, buf: Buffer, tick: int) -> None:
    stack.db.set_tick(buf=buf.number, tick=tick)


def _detach_event(nvim: Nvim, stack: Stack, buf: Buffer) -> None:
    stack.db.rm_buf(buf=buf.number)


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
    "nvim_buf_changedtick_event": _changed_event,
    "nvim_buf_detach_event": _detach_event,
}
