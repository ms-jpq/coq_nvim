from concurrent.futures import CancelledError, Future
from threading import Lock
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
from uuid import UUID, uuid4

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.logging import log
from std2.pickle import DecodeError, new_decoder

from ...registry import autocmd, enqueue_event, pool, rpc
from ...shared.runtime import Metric
from ...shared.timeit import timeit
from ...shared.types import Context, NvimPos
from ..context import context
from ..edit import edit
from ..nvim.completions import UserData, VimCompletion, complete
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


@rpc(blocking=True)
def _cmp(nvim: Nvim, stack: Stack, col: int, comp: Sequence[VimCompletion]) -> None:
    complete(nvim, col=col, comp=comp)


_LOCK = Lock()
_FUTS: MutableSequence[Future] = []


def comp_func(
    nvim: Nvim, stack: Stack, change_id: UUID, commit_id: UUID, manual: bool
) -> None:
    with _LOCK:
        for f1 in _FUTS:
            f1.cancel()
        _FUTS.clear()

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
    if ctx and (manual or should):
        _, col = ctx.position
        complete(nvim, col=col - 1, comp=())
        state(context=ctx)

        @timeit("COLLECT")
        def cont() -> None:
            try:
                if ctx:
                    f1 = stack.supervisor.collect(ctx, manual=manual)
                    with _LOCK:
                        _FUTS.append(f1)
                    try:
                        metrics = cast(Sequence[Metric], f1.result())
                    except CancelledError:
                        pass
                    else:
                        s = state()
                        if s.context == ctx:
                            with timeit("TRANS"):
                                vim_comps = tuple(
                                    trans(stack, context=ctx, metrics=metrics)
                                )
                            enqueue_event(_cmp, col, vim_comps)
            except Exception as e:
                log.exception("%s", e)

        f2 = pool.submit(cont)
        with _LOCK:
            _FUTS.append(f2)
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

