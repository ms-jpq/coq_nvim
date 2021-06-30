from concurrent.futures import CancelledError
from typing import Any, Literal, Mapping, Optional, Sequence, Tuple, Union, cast
from uuid import UUID

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.logging import log
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, enqueue_event, pool, rpc
from ...shared.nvim.completions import VimCompletion, complete
from ...shared.runtime import Metric
from ...shared.timeit import timeit
from ...shared.types import Context, NvimPos
from ..context import context
from ..edit import edit
from ..runtime import Stack
from ..trans import trans
from ..types import UserData


def _should_cont(
    inserted: Optional[NvimPos], prev: Optional[Context], cur: Context
) -> bool:
    if prev and prev.changedtick == cur.changedtick:
        return False
    elif cur.position == inserted:
        return False
    else:
        return (cur.words_before or cur.syms_before) != ""


@rpc(blocking=True)
def _cmp(
    nvim: Nvim, stack: Stack, uid: UUID, col: int, comp: Sequence[VimCompletion]
) -> None:
    complete(nvim, col=col, comp=comp)
    stack.state.commit = uid


def comp_func(nvim: Nvim, stack: Stack, manual: bool) -> None:
    for fut in stack.state.futs:
        fut.cancel()
    stack.state.futs = ()

    with timeit("GEN CTX"):
        ctx = context(nvim, options=stack.settings.match, db=stack.bdb)
    should = (
        _should_cont(
            stack.state.inserted,
            prev=stack.state.cur,
            cur=ctx,
        )
        if ctx
        else False
    )
    if ctx and (manual or should):
        _, col = stack.state.request = ctx.position
        stack.state.cur = ctx

        complete(nvim, col=col - 1, comp=())
        fut = stack.supervisor.collect(ctx, manual=manual)

        @timeit("COLLECT")
        def cont() -> None:
            try:
                try:
                    metrics = cast(Sequence[Metric], fut.result())
                except CancelledError:
                    pass
                else:
                    if ctx and stack.state.cur == ctx:
                        _, col = ctx.position
                        with timeit("TRANS"):
                            vim_comps = tuple(
                                trans(stack, context=ctx, metrics=metrics)
                            )
                        enqueue_event(_cmp, ctx.uid, col, vim_comps)
            except Exception as e:
                log.exception("%s", e)

        stack.state.futs = (pool.submit(cont),)
    else:
        stack.state.inserted = None


@rpc(blocking=True)
def omnifunc(
    nvim: Nvim, stack: Stack, args: Tuple[Tuple[Literal[0, 1], str]]
) -> Union[int, Sequence[Mapping[str, Any]]]:
    (op, _), *_ = args

    if op == 1:
        return -1
    else:
        comp_func(nvim, stack=stack, manual=True)
        return ()


@rpc(blocking=True)
def _comp_done(nvim: Nvim, stack: Stack, event: Mapping[str, Any]) -> None:
    data = event.get("user_data")
    if data:
        try:
            user_data: UserData = decode(UserData, data, decoders=BUILTIN_DECODERS)
        except DecodeError:
            pass
        else:
            edit(nvim, stack=stack, data=user_data)


autocmd("CompleteDone") << f"lua {_comp_done.name}(vim.v.completed_item)"

