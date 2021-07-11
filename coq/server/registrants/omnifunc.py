from asyncio import CancelledError, Event, Task, gather, sleep
from contextlib import suppress
from queue import SimpleQueue
from typing import Any, Literal, Mapping, Optional, Sequence, Tuple, Union, cast
from uuid import uuid4

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go
from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.pickle import DecodeError, new_decoder

from ...registry import atomic, autocmd, rpc
from ...shared.timeit import timeit as l_timeit
from ...shared.types import Context, NvimPos
from ..context import context
from ..edit import edit
from ..nvim.completions import UserData, complete
from ..rt_types import Stack
from ..state import State, state
from ..trans import trans

q: SimpleQueue = SimpleQueue()
_QUED = Tuple[Context, bool]


@rpc(blocking=True)
def _launch_loop(nvim: Nvim, stack: Stack) -> None:
    async def cont() -> None:
        event = Event()
        qued: Optional[_QUED] = None
        task: Optional[Task] = None

        async def c0(ctx: Context, manual: bool) -> None:
            _, col = ctx.position
            await stack.supervisor.interrupt()
            metrics = await stack.supervisor.collect(ctx, manual=manual)
            s = state()
            if s.change_id == ctx.change_id:
                vim_comps = tuple(trans(stack, context=ctx, metrics=metrics))
                await async_call(nvim, complete, nvim, col=col, comp=vim_comps)

        async def c1() -> None:
            nonlocal qued
            while True:
                qued = await run_in_executor(q.get)
                event.set()

        async def c2() -> None:
            nonlocal task
            while True:
                await event.wait()
                event.clear()
                if task:
                    task.cancel()
                    while not task.done():
                        await sleep(0)
                    with suppress(CancelledError):
                        await task
                if qued:
                    ctx, manual = qued
                    task = cast(Task, go(nvim, aw=c0(ctx, manual=manual)))

        await gather(c1(), c2())

    go(nvim, aw=cont())


atomic.exec_lua(f"{_launch_loop.name}()", ())


def _should_cont(inserted: Optional[NvimPos], prev: Context, cur: Context) -> bool:
    if prev.change_id == cur.change_id:
        return False
    elif cur.position == inserted:
        return False
    else:
        return (cur.words_before or cur.syms_before) != ""


def comp_func(nvim: Nvim, stack: Stack, s: State, manual: bool) -> None:
    with l_timeit("GEN CTX"):
        ctx = context(nvim, options=stack.settings.match, state=s)
    should = _should_cont(s.inserted, prev=s.context, cur=ctx) if ctx else False
    _, col = ctx.position
    complete(nvim, col=col - 1, comp=())

    if manual or should:
        state(context=ctx)
        q.put((ctx, manual))
    else:
        state(inserted=(-1, -1))


@rpc(blocking=True)
def omnifunc(
    nvim: Nvim, stack: Stack, args: Tuple[Tuple[Literal[0, 1], str]]
) -> Union[int, Sequence[Mapping[str, Any]]]:
    (op, _), *_ = args

    if op == 1:
        return -1
    else:
        s = state(commit_id=uuid4())
        comp_func(nvim, stack=stack, manual=True, s=s)
        return ()


_DECODER = new_decoder(UserData)


@rpc(blocking=True)
def _comp_done(nvim: Nvim, stack: Stack, event: Mapping[str, Any]) -> None:
    data = event.get("user_data")
    if data:
        try:
            user_data: UserData = _DECODER(data)
        except DecodeError as e:
            log.warn("%s", e)
        else:
            s = state()
            if user_data.change_uid == s.change_id:
                inserted = edit(nvim, stack=stack, state=s, data=user_data)
                state(inserted=inserted, commit_id=uuid4())
            else:
                log.warn("%s", "delayed completion")


autocmd("CompleteDone") << f"lua {_comp_done.name}(vim.v.completed_item)"

