from asyncio import Task
from typing import Any, Literal, Mapping, Optional, Sequence, Tuple, Union, cast
from uuid import UUID, uuid4

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go
from pynvim_pp.logging import log
from std2.pickle import DecodeError, new_decoder

from ...registry import autocmd, rpc
from ...shared.timeit import timeit
from ...shared.types import Context, NvimPos
from ..context import context
from ..edit import edit
from ..nvim.completions import UserData, complete
from ..rt_types import Stack
from ..state import state
from ..trans import trans


def _should_cont(inserted: Optional[NvimPos], prev: Context, cur: Context) -> bool:
    if prev.change_id == cur.change_id:
        return False
    elif cur.position == inserted:
        return False
    else:
        return (cur.words_before or cur.syms_before) != ""


_TASK: Optional[Task] = None


def comp_func(
    nvim: Nvim, stack: Stack, change_id: UUID, commit_id: UUID, manual: bool
) -> None:
    global _TASK
    if _TASK:
        _TASK.cancel()

    s = state()
    with timeit("GEN CTX"):
        ctx = context(
            nvim,
            options=stack.settings.match,
            db=stack.bdb,
            change_id=change_id,
            commit_id=commit_id,
        )
    should = (
        _should_cont(
            s.inserted,
            prev=s.context,
            cur=ctx,
        )
        if ctx
        else False
    )
    _, col = ctx.position
    complete(nvim, col=col - 1, comp=())

    if manual or should:
        state(context=ctx)

        async def cont() -> None:
            metrics = await stack.supervisor.collect(ctx, manual=manual)
            s = state()
            if s.change_id == ctx.change_id:
                with timeit("TRANS"):
                    vim_comps = tuple(trans(stack, context=ctx, metrics=metrics))
                await async_call(nvim, complete, nvim, col=col, comp=vim_comps)

        _TASK = cast(Task, go(cont()))
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
        comp_func(
            nvim, stack=stack, manual=True, commit_id=s.commit_id, change_id=s.change_id
        )
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
                inserted = edit(nvim, stack=stack, context=s.context, data=user_data)
                state(inserted=inserted, commit_id=uuid4())
            else:
                log.warn("%s", "delayed completion")


autocmd("CompleteDone") << f"lua {_comp_done.name}(vim.v.completed_item)"

