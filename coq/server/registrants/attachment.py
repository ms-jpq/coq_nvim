from contextlib import suppress
from typing import Sequence

from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import buf_filetype, buf_get_option, buf_name, cur_buf, list_bufs

from ...registry import atomic, autocmd, rpc
from ...server.context import edit_env
from ..runtime import Stack


@rpc(blocking=True)
def _buf_enter(nvim: Nvim, stack: Stack) -> None:
    with suppress(NvimError):
        buf = cur_buf(nvim)
        listed = buf_get_option(nvim, buf=buf, key="buflisted")
        if listed:
            nvim.api.buf_attach(buf, True, {})
            env = edit_env(nvim, buf=buf)
            stack.state.env = env


autocmd("BufEnter") << f"lua {_buf_enter.name}()"


@rpc(blocking=True)
def _buf_new_init(nvim: Nvim, stack: Stack) -> None:
    with suppress(NvimError):
        for buf in list_bufs(nvim, listed=True):
            nvim.api.buf_attach(buf, True, {})


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

    stack.bdb.set_lines(
        file=file,
        filetype=filetype,
        lo=lo,
        hi=hi,
        lines=lines,
        unifying_chars=stack.settings.match.unifying_chars,
    )


def _changed_event(nvim: Nvim, stack: Stack, buf: Buffer, tick: int) -> None:
    pass


def _detach_event(nvim: Nvim, stack: Stack, buf: Buffer) -> None:
    pass


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
    "nvim_buf_changedtick_event": _changed_event,
    "nvim_buf_detach_event": _detach_event,
}

