from concurrent.futures import CancelledError
from typing import Optional, Sequence

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.logging import log

from ...registry import autocmd, enqueue_event, pool, rpc
from ...shared.nvim.completions import complete
from ...shared.types import Completion, Context, NvimPos
from ..context import context
from ..runtime import Stack
from ..trans import trans


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
        comp = trans(stack, context=ctx, completions=completions)
        complete(nvim, col=col, comp=comp)


@rpc(blocking=True)
def _txt_changed(nvim: Nvim, stack: Stack) -> None:
    prev: Optional[Context] = None
    if stack.state.cur:
        prev, f = stack.state.cur
        f.cancel()

    ctx = context(
        nvim,
        unifying_chars=stack.settings.match.unifying_chars,
        cwd=stack.state.cwd,
    )
    if _should_cont(stack.state.inserted, prev=prev, cur=ctx):
        fut = stack.supervisor.collect(ctx)
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


autocmd("TextChangedI", "TextChangedP") << f"lua {_txt_changed.name}()"

