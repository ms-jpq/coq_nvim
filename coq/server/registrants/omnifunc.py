from concurrent.futures import CancelledError
from typing import Any, Literal, Mapping, Optional, Sequence, Tuple, TypedDict, Union

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.logging import log
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, enqueue_event, pool, rpc, settings
from ...shared.nvim.completions import complete
from ...shared.types import Completion, Context, NvimPos
from ...shared.timeit import timeit
from ..context import context
from ..edit import edit
from ..runtime import Stack
from ..trans import trans
from ..types import UserData


def _should_cont(
    inserted: Optional[NvimPos], prev: Optional[Context], cur: Context
) -> bool:
    if prev and cur.position == prev.position:
        return False
    elif cur.position == inserted:
        return False
    else:
        return cur.line_before != "" and not cur.line_before.isspace()


@rpc(blocking=True)
def _cmp(nvim: Nvim, stack: Stack, completions: Sequence[Completion]) -> None:
    if stack.state.inserting and stack.state.cur:
        ctx, _ = stack.state.cur
        _, col = ctx.position
        with timeit(0, "TRANS"):
            comp = trans(stack, context=ctx, completions=completions)
        complete(nvim, col=col, comp=comp)


def comp_func(nvim: Nvim, stack: Stack, manual: bool) -> None:
    prev: Optional[Context] = None
    if stack.state.cur:
        prev, f = stack.state.cur
        f.cancel()

    ctx = context(
        nvim,
        unifying_chars=stack.settings.match.unifying_chars,
        cwd=stack.state.cwd,
    )
    if manual or _should_cont(stack.state.inserted, prev=prev, cur=ctx):
        fut = stack.supervisor.collect(ctx, manual=manual)
        stack.state.cur = (ctx, fut)

        def cont() -> None:
            try:
                try:
                    cmps = fut.result()
                except CancelledError:
                    pass
                else:
                    if stack.state.cur:
                        prev, _ = stack.state.cur
                        if prev == ctx:
                            enqueue_event(_cmp, cmps)
            except Exception as e:
                log.exception("%s", e)

        pool.submit(cont)
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


settings["completefunc"] = omnifunc.name


@rpc(blocking=True)
def _txt_changed(nvim: Nvim, stack: Stack) -> None:
    comp_func(nvim, stack=stack, manual=False)


autocmd("TextChangedI", "TextChangedP") << f"lua {_txt_changed.name}()"


class _CompEvent(TypedDict, total=False):
    user_data: Any


@rpc(blocking=True)
def _comp_done(nvim: Nvim, stack: Stack, event: _CompEvent) -> None:
    data = event.get("user_data")
    if data:
        try:
            user_data: UserData = decode(UserData, data, decoders=BUILTIN_DECODERS)
        except DecodeError:
            pass
        else:
            edit(nvim, stack=stack, data=user_data)


autocmd("CompleteDone") << f"lua {_comp_done.name}(vim.v.completed_item)"

