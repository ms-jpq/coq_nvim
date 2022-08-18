from asyncio import gather
from contextlib import suppress
from dataclasses import dataclass
from itertools import count
from queue import SimpleQueue
from typing import Mapping, Sequence, Tuple, cast
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer, NvimError
from pynvim_pp.api import buf_get_option, cur_buf
from pynvim_pp.atomic import Atomic
from pynvim_pp.lib import async_call, awrite, go
from pynvim_pp.logging import with_suppress
from std2.asyncio import to_thread

from ...lang import LANG
from ...registry import NAMESPACE, atomic, autocmd, rpc
from ...shared.timeit import timeit
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


_ = autocmd("BufEnter", "InsertEnter") << f"lua {NAMESPACE}.{_buf_enter.name}()"
atomic.exec_lua(f"{NAMESPACE}.{_buf_enter.name}()", ())

_q: SimpleQueue = SimpleQueue()
_id_gen = count()
_current_id = -1


@dataclass(frozen=True)
class _Qmsg:
    id: int
    pending: bool
    buf: Buffer
    range: Tuple[int, int]
    lines: Sequence[str]


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


@rpc(blocking=True)
def _coq_listener(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        while True:
            with with_suppress():
                qmsg: _Qmsg = await to_thread(_q.get)
                if qmsg.id != _current_id:
                    pass
                else:
                    with timeit("POLL"), suppress(NvimError):
                        (mode, comp_mode, filetype, filename), _ = await gather(
                            _status(nvim, qmsg.buf), stack.supervisor.interrupt()
                        )

                        lo, hi = qmsg.range
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
                                filetype=filetype,
                                filename=filename,
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
                            stack.settings.completion.always
                            and not qmsg.pending
                            and mode.startswith("i")
                            and comp_mode in {"", "eval", "function", "ctrl_x"}
                        ):
                            comp_func(nvim, s=s, manual=False)

    go(nvim, aw=cont())


atomic.exec_lua(f"{NAMESPACE}.{_coq_listener.name}()", ())


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
    global _current_id
    _current_id = next(_id_gen)
    msg = _Qmsg(
        id=_current_id,
        pending=pending,
        buf=buf,
        range=(lo, hi),
        lines=lines,
    )
    _q.put(msg)


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
}
