from contextlib import suppress
from dataclasses import dataclass
from queue import SimpleQueue
from typing import Sequence, Tuple
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import buf_filetype, buf_get_option, cur_buf
from pynvim_pp.lib import awrite, go
from pynvim_pp.logging import with_suppress
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


@dataclass(frozen=True)
class _Qmsg:
    mode: str
    comp_mode: str
    pending: bool
    buf: Buffer
    range: Tuple[int, int]
    lines: Sequence[str]
    filetype: str


@rpc(blocking=True)
def _listener(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        while True:
            with with_suppress():
                qmsg: _Qmsg = await run_in_executor(q.get)
                lo, hi = qmsg.range
                await stack.supervisor.interrupt()

                size = sum(map(len, qmsg.lines))
                heavy_bufs = (
                    {qmsg.buf.number}
                    if size > stack.settings.limits.index_cutoff
                    else set()
                )
                os = state()
                s = state(change_id=uuid4(), nono_bufs=heavy_bufs)

                if qmsg.buf.number not in s.nono_bufs:
                    await stack.bdb.set_lines(
                        qmsg.buf.number,
                        filetype=qmsg.filetype,
                        lo=lo,
                        hi=hi,
                        lines=qmsg.lines,
                        unifying_chars=stack.settings.match.unifying_chars,
                    )

                if (
                    qmsg.buf.number in s.nono_bufs
                    and qmsg.buf.number not in os.nono_bufs
                ):
                    msg = LANG(
                        "buf 2 fat",
                        size=size,
                        limit=stack.settings.limits.index_cutoff,
                    )
                    await awrite(nvim, msg)

                if (
                    not qmsg.pending
                    and qmsg.mode.startswith("i")
                    and qmsg.comp_mode in ("", "ctrl_x", "function", "eval")
                ):
                    comp_func(nvim, stack=stack, s=s, manual=False)

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
    with suppress(NvimError):
        filetype = buf_filetype(nvim, buf=buf)
        mode = nvim.api.get_mode()["mode"]
        comp_mode = nvim.funcs.complete_info(("mode",))["mode"]
        msg = _Qmsg(
            mode=mode,
            comp_mode=comp_mode,
            pending=pending,
            buf=buf,
            range=(lo, hi),
            lines=lines,
            filetype=filetype,
        )
        q.put(msg)


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
}
