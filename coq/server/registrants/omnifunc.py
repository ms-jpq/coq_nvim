from asyncio import gather, sleep, wait
from dataclasses import replace
from typing import AbstractSet, Any, Literal, Mapping, Sequence, Union
from uuid import UUID, uuid4

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.api import (
    ExtMark,
    buf_get_lines,
    buf_set_extmarks,
    clear_ns,
    create_ns,
    cur_buf,
)
from pynvim_pp.lib import async_call, encode, go
from pynvim_pp.logging import log
from std2.asyncio import cancel
from std2.pickle.decoder import new_decoder
from std2.pickle.types import DecodeError

from ...lsp.requests.command import cmd
from ...lsp.requests.resolve import resolve
from ...registry import NAMESPACE, autocmd, rpc
from ...shared.runtime import Metric
from ...shared.timeit import timeit
from ...shared.types import Context, ExternLSP, ExternPath
from ..completions import complete
from ..context import context
from ..edit import NS, edit
from ..rt_types import Stack
from ..state import State, state
from ..trans import trans


def _should_cont(
    state: State, prev: Context, cur: Context, skip_after: AbstractSet[str]
) -> bool:
    if cur.manual:
        return True
    elif prev.change_id == cur.change_id:
        return False
    elif cur.position == state.inserted_pos:
        if isinstance(extern := state.last_edit.comp.extern, ExternPath):
            return extern.is_dir
        else:
            return False
    elif any(cur.line_before.endswith(token) for token in skip_after):
        return False
    elif cur.syms_before != "":
        return True
    else:
        have_space = (
            bool(stripped := cur.line_before.rstrip())
            and len(cur.line_before) - len(stripped) <= 1
        )
        return have_space


async def comp_func(nvim: Nvim, stack: Stack, s: State, manual: bool) -> None:
    with timeit("**OVERALL**"):
        ctx = await async_call(
            nvim,
            lambda: context(
                nvim,
                options=stack.settings.match,
                state=s,
                manual=manual,
            ),
        )
        should = (
            _should_cont(
                s,
                prev=s.context,
                cur=ctx,
                skip_after=stack.settings.completion.skip_after,
            )
            if ctx
            else False
        )
        _, col = ctx.position

        if should:
            state(context=ctx)
            metrics, _ = await gather(
                stack.supervisor.collect(ctx),
                async_call(
                    nvim,
                    lambda: complete(nvim, stack=stack, col=col, comps=()),
                )
                if stack.settings.display.pum.fast_close
                else sleep(0),
            )
            s = state()
            if s.change_id == ctx.change_id:
                vim_comps = tuple(
                    trans(
                        stack,
                        pum_width=s.pum_width,
                        context=ctx,
                        metrics=metrics,
                    )
                )
                await async_call(
                    nvim,
                    lambda: complete(nvim, stack=stack, col=col, comps=vim_comps),
                )
        else:
            await async_call(
                nvim, lambda: complete(nvim, stack=stack, col=col, comps=())
            )
            state(inserted_pos=(-1, -1))


@rpc(blocking=True)
def omnifunc(
    nvim: Nvim, stack: Stack, findstart: Literal[0, 1], base: str
) -> Union[int, Sequence[Mapping[str, Any]]]:
    if findstart:
        return -1
    else:
        s = state(commit_id=uuid4())
        go(nvim, aw=comp_func(nvim, stack=stack, manual=True, s=s))
        return ()


async def _resolve(nvim: Nvim, stack: Stack, metric: Metric) -> Metric:
    if not isinstance((extern := metric.comp.extern), ExternLSP):
        return metric
    else:
        if comp := stack.lru.get(metric.comp.uid):
            return replace(
                metric,
                comp=replace(metric.comp, secondary_edits=comp.secondary_edits),
            )
        else:
            done, not_done = await wait(
                (go(nvim, aw=resolve(nvim, extern=extern)),),
                timeout=stack.settings.clients.lsp.resolve_timeout,
            )
            await cancel(*not_done)
            comp = (await done.pop()) if done else None
            if not comp:
                return metric
            else:
                return replace(
                    metric,
                    comp=replace(metric.comp, secondary_edits=comp.secondary_edits),
                )


_UDECODER = new_decoder[UUID](UUID)


@rpc(blocking=True)
def _comp_done(nvim: Nvim, stack: Stack, event: Mapping[str, Any]) -> None:
    data = event.get("user_data")
    if data:
        try:
            uid = _UDECODER(data)
        except DecodeError:
            pass
        else:
            s = state()
            if metric := stack.metrics.get(uid):
                row, col = s.context.position
                buf = cur_buf(nvim)
                ns = create_ns(nvim, ns=NS)
                clear_ns(nvim, buf=buf, id=ns)
                before, *_ = buf_get_lines(nvim, buf=buf, lo=row, hi=row + 1)
                e1 = ExtMark(
                    idx=1,
                    begin=(row, 0),
                    end=(row, col),
                    meta={},
                )
                e2 = ExtMark(
                    idx=2,
                    begin=(row, col),
                    end=(row, len(encode(before))),
                    meta={},
                )
                buf_set_extmarks(nvim, buf=buf, id=ns, marks=(e1, e2))

                async def cont() -> None:
                    if metric:
                        new_metric = await _resolve(nvim, stack=stack, metric=metric)

                        async def c2() -> None:
                            if isinstance(
                                (extern := new_metric.comp.extern), ExternLSP
                            ):
                                await cmd(nvim, extern=extern)

                        def c1() -> None:
                            if new_metric.comp.uid in stack.metrics:
                                inserted_at = edit(
                                    nvim,
                                    stack=stack,
                                    state=s,
                                    metric=new_metric,
                                    synthetic=False,
                                )
                                ins_pos = inserted_at or (-1, -1)
                                state(
                                    inserted_pos=ins_pos,
                                    last_edit=new_metric,
                                    commit_id=uuid4(),
                                )
                                go(nvim, aw=c2())
                            else:
                                log.warn("%s", "delayed completion")

                        await async_call(nvim, c1)

                go(nvim, aw=cont())


_ = (
    autocmd("CompleteDone")
    << f"lua {NAMESPACE}.{_comp_done.name}(vim.v.completed_item)"
)
