from asyncio import CancelledError, Condition, Task, gather
from queue import SimpleQueue
from typing import Any, Literal, Mapping, Optional, Sequence, Tuple, Union, cast
from uuid import uuid4

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go
from pynvim_pp.logging import log, with_suppress
from std2.asyncio import cancel, run_in_executor
from std2.pickle import DecodeError, new_decoder

from ...registry import atomic, autocmd, rpc
from ...shared.timeit import timeit
from ...shared.types import Context, NvimPos
from ..context import context
from ..edit import edit
from ..nvim.completions import UserData, complete
from ..rt_types import Stack
from ..state import State, state
from ..trans import trans

_Q: SimpleQueue = SimpleQueue()


def _should_cont(inserted: Optional[NvimPos], prev: Context, cur: Context) -> bool:
    if cur.manual:
        return True
    elif prev.change_id == cur.change_id:
        return False
    elif cur.position == inserted:
        return False
    else:
        return (cur.words_before or cur.syms_before) != ""


@rpc(blocking=True)
def _launch_loop(nvim: Nvim, stack: Stack) -> None:
    task: Optional[Task] = None

    async def cont() -> None:
        cond = Condition()
        incoming: Optional[Tuple[State, bool]] = None

        async def c0(ctx: Context) -> None:
            s = None
            try:
                metrics = await stack.supervisor.collect(ctx)
                s = state()
                if s.change_id == ctx.change_id:
                    _, col = s.context.position
                    vim_comps = tuple(trans(stack, context=ctx, metrics=metrics))
                else:
                    vim_comps = ()
                await async_call(nvim, lambda: complete(nvim, col=col, comp=vim_comps))
            except CancelledError:
                _, col = (s or state()).context.position
                await async_call(nvim, lambda: complete(nvim, col=col, comp=()))

        async def c1() -> None:
            nonlocal incoming
            while True:
                with with_suppress():
                    incoming = await run_in_executor(_Q.get)
                    async with cond:
                        cond.notify_all()

        async def c2() -> None:
            nonlocal task
            while True:
                with with_suppress():
                    async with cond:
                        await cond.wait()

                    if task:
                        await cancel(task)

                    if incoming:
                        s, manual = incoming
                        ctx = await async_call(
                            nvim,
                            lambda: context(
                                nvim,
                                db=stack.bdb,
                                options=stack.settings.match,
                                state=s,
                                manual=manual,
                            ),
                        )
                        should = (
                            _should_cont(s.inserted, prev=s.context, cur=ctx)
                            if ctx
                            else False
                        )

                        if should:
                            state(context=ctx)
                            task = cast(Task, go(nvim, aw=c0(ctx)))
                        else:
                            state(inserted=(-1, -1))

        await gather(c1(), c2())

    go(nvim, aw=cont())


atomic.exec_lua(f"{_launch_loop.name}()", ())


def comp_func(nvim: Nvim, stack: Stack, s: State, manual: bool) -> None:
    _Q.put((s, manual))


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
                inserted = edit(
                    nvim, stack=stack, state=s, data=user_data, synthetic=False
                )
                state(inserted=inserted, commit_id=uuid4())
            else:
                log.warn("%s", "delayed completion")


autocmd("CompleteDone") << f"lua {_comp_done.name}(vim.v.completed_item)"
