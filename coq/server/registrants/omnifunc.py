from concurrent.futures import CancelledError, Future
from typing import (
    Any,
    Literal,
    Mapping,
    MutableSequence,
    Optional,
    Sequence,
    Tuple,
    Union,
    cast,
)
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
from ..rt_types import Stack
from ..state import state
from ..trans import trans
from ..types import UserData


def _should_cont(inserted: Optional[NvimPos], prev: Context, cur: Context) -> bool:
    if prev.changedtick == cur.changedtick:
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
    state(commit=uid)


_FUTS: MutableSequence[Future] = []


def _comp_func(nvim: Nvim, stack: Stack, manual: bool) -> None:
    for f1 in _FUTS:
        f1.cancel()
    _FUTS.clear()

    s = state()
    with timeit("GEN CTX"):
        ctx = context(nvim, options=stack.settings.match, db=stack.bdb)
    should = (
        _should_cont(
            s.inserted,
            prev=s.context,
            cur=ctx,
        )
        if ctx
        else False
    )
    if ctx and (manual or should):
        _, col = ctx.position
        complete(nvim, col=col - 1, comp=())

        state(context=ctx)
        f1 = stack.supervisor.collect(ctx, manual=manual)
        _FUTS.append(f1)

        @timeit("COLLECT")
        def cont() -> None:
            try:
                try:
                    metrics = cast(Sequence[Metric], f1.result())
                except CancelledError:
                    pass
                else:
                    s = state()
                    if ctx and s.context == ctx:
                        with timeit("TRANS"):
                            vim_comps = tuple(
                                trans(stack, context=ctx, metrics=metrics)
                            )
                        enqueue_event(_cmp, ctx.uid, col, vim_comps)
            except Exception as e:
                log.exception("%s", e)

        f2 = pool.submit(cont)
        _FUTS.append(f2)
    else:
        state(inserted=(-1, -1))


def comp_func(nvim: Nvim, stack: Stack, manual: bool) -> None:
    mode: str = nvim.api.get_mode()["mode"]
    if mode.startswith("i"):
        _comp_func(nvim, stack=stack, manual=manual)


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
            s = state()
            if user_data.commit_uid == s.commit:
                inserted = edit(nvim, stack=stack, context=s.context, data=user_data)
                state(inserted=inserted)
            else:
                log.warn("%s", "delayed completion")


autocmd("CompleteDone") << f"lua {_comp_done.name}(vim.v.completed_item)"

