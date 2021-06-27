from concurrent.futures import CancelledError
from typing import Any, Literal, Mapping, Optional, Sequence, Tuple, Union

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.logging import log
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, enqueue_event, pool, rpc
from ...shared.nvim.completions import complete
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, NvimPos
from ..context import context
from ..edit import edit
from ..runtime import Stack
from ..trans import trans
from ..types import UserData


def _should_cont(
    inserted: Optional[NvimPos], prev: Optional[Context], cur: Context, pum_open: bool
) -> bool:
    if prev and prev.changedtick == cur.changedtick:
        return False
    elif pum_open and prev and prev.position == cur.position:
        return False
    elif cur.position == inserted:
        return False
    else:
        return (cur.words_before or cur.syms_before) != ""


@rpc(blocking=True)
def _cmp(nvim: Nvim, stack: Stack, completions: Sequence[Completion]) -> None:
    ctx = stack.state.cur
    if ctx:
        _, col = ctx.position
        with timeit("RANK"):
            comp = trans(nvim, stack=stack, context=ctx, completions=completions)
            complete(nvim, col=col, comp=comp)
            stack.state.commit = ctx.uid


def _comp_func(nvim: Nvim, stack: Stack, manual: bool, pum_open: bool) -> None:
    for fut in stack.state.futs:
        fut.cancel()
    stack.state.futs = ()

    ctx = context(
        nvim,
        db=stack.bdb,
        unifying_chars=stack.settings.match.unifying_chars,
        cwd=stack.state.cwd,
    )
    should = _should_cont(
        stack.state.inserted,
        prev=stack.state.cur,
        cur=ctx,
        pum_open=pum_open,
    )
    if manual or should:
        stack.state.cur = ctx

        _, col = ctx.position
        complete(nvim, col=col - 1, comp=())
        fut = stack.supervisor.collect(ctx, manual=manual)

        @timeit("WAIT")
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
        _comp_func(nvim, stack=stack, manual=True, pum_open=False)
        return ()


@rpc(blocking=True)
def _txt_changed(nvim: Nvim, stack: Stack, pum_open: bool) -> None:
    with timeit("BEGIN"):
        _comp_func(nvim, stack=stack, manual=False, pum_open=pum_open)


autocmd("TextChangedI") << f"lua {_txt_changed.name}(false)"
autocmd("TextChangedP") << f"lua {_txt_changed.name}(true)"


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

