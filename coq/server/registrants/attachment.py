from concurrent.futures import CancelledError
from typing import Sequence

from pynvim import Nvim
from pynvim.api import Buffer
from pynvim_pp.api import buf_filetype, buf_get_option, buf_name, cur_buf, list_bufs
from pynvim_pp.logging import log

from ...registry import atomic, autocmd, enqueue_event, pool, rpc
from ...shared.nvim.completions import complete
from ...shared.types import Completion
from ..context import context
from ..runtime import Stack
from ..trans import trans


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


@rpc(blocking=True)
def _cmp(nvim: Nvim, stack: Stack, completions: Sequence[Completion]) -> None:
    if stack.state.cur:
        ctx, _ = stack.state.cur
        _, col = ctx.position
        comp = trans(stack, context=ctx, completions=completions)
        complete(nvim, col=col, comp=comp)


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
        file=file,
        filetype=filetype,
        lo=lo,
        hi=hi,
        lines=lines,
        unifying_chars=stack.settings.match.unifying_chars,
    )

    if stack.state.inserting:
        if buf == cur_buf(nvim):
            if stack.state.cur:
                _, f = stack.state.cur
                f.cancel()

            ctx = context(
                nvim,
                unifying_chars=stack.settings.match.unifying_chars,
                cwd=stack.state.cwd,
                buf=buf,
                filename=file,
                filetype=filetype,
            )
            fut = stack.supervisor.collect(ctx)
            stack.state.cur = (ctx, fut)

            def cont() -> None:
                try:
                    try:
                        cmps = fut.result()
                    except CancelledError:
                        pass
                    else:
                        if stack.state.cur == ctx:
                            enqueue_event(_cmp, cmps)
                except Exception as e:
                    log.exception("%s", e)

            pool.submit(cont)


def _changed_event(nvim: Nvim, stack: Stack, buf: Buffer, tick: int) -> None:
    pass


def _detach_event(nvim: Nvim, stack: Stack, buf: Buffer) -> None:
    pass


BUF_EVENTS = {
    "nvim_buf_lines_event": _lines_event,
    "nvim_buf_changedtick_event": _changed_event,
    "nvim_buf_detach_event": _detach_event,
}

