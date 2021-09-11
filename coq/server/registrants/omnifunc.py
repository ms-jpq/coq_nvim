from asyncio import Event, Lock, Task, gather, sleep, wait
from asyncio.events import AbstractEventLoop
from contextlib import suppress
from dataclasses import replace
from itertools import takewhile
from queue import SimpleQueue
from typing import AbstractSet, Any, Literal, Mapping, Optional, Sequence, Tuple, Union
from uuid import uuid4

from pynvim.api import Buffer, Nvim
from pynvim.api.common import NvimError
from pynvim_pp.api import (
    ExtMark,
    buf_get_extmarks,
    buf_get_lines,
    buf_get_text,
    buf_get_var,
    buf_set_extmarks,
    clear_ns,
    create_ns,
    cur_buf,
)
from pynvim_pp.lib import async_call, encode, go
from pynvim_pp.logging import log, with_suppress
from std2.asyncio import cancel, run_in_executor
from std2.pickle import DecodeError, new_decoder

from ...lsp.requests.preview import request
from ...registry import atomic, autocmd, rpc
from ...shared.parse import is_word
from ...shared.timeit import timeit
from ...shared.types import Context, Edit, Extern, NvimPos, RangeEdit
from ..context import context
from ..edit import NS, edit
from ..nvim.completions import UserData, complete
from ..rt_types import Stack
from ..state import Repeat, State, state
from ..trans import trans

_Q: SimpleQueue = SimpleQueue()


def _should_cont(inserted: Optional[NvimPos], prev: Context, cur: Context) -> bool:
    if cur.manual:
        return True
    elif prev.change_id == cur.change_id:
        return False
    elif cur.position == inserted:
        return False
    elif cur.syms_before != "":
        return True
    else:
        stripped = cur.line_before.rstrip()
        return bool(stripped) and len(cur.line_before) - len(stripped) <= 1


@rpc(blocking=True)
def _launch_loop(nvim: Nvim, stack: Stack) -> None:
    task: Optional[Task] = None
    incoming: Optional[Tuple[State, bool]] = None

    async def cont() -> None:
        lock, event = Lock(), Event()

        async def c0(s: State, manual: bool) -> None:
            with with_suppress(), timeit("**OVERALL**"):
                if lock.locked():
                    log.warn("%s", "SHOULD NOT BE LOCKED <><> OODA")
                async with lock:
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
                    _, col = ctx.position

                    if should:
                        state(context=ctx)
                        await stack.supervisor.interrupt()
                        metrics, _ = await gather(
                            stack.supervisor.collect(ctx),
                            async_call(nvim, lambda: complete(nvim, col=col, comp=()))
                            if stack.settings.display.pum.fast_close
                            else sleep(0),
                        )
                        s = state()
                        if s.change_id == ctx.change_id:
                            vim_comps = tuple(
                                trans(stack, context=ctx, metrics=metrics)
                            )
                            await async_call(
                                nvim, lambda: complete(nvim, col=col, comp=vim_comps)
                            )
                    else:
                        await async_call(nvim, lambda: complete(nvim, col=col, comp=()))
                        state(inserted=(-1, -1))

        async def c1() -> None:
            nonlocal incoming
            while True:
                with with_suppress():
                    incoming = await run_in_executor(_Q.get)
                    event.set()

        async def c2() -> None:
            nonlocal task
            while True:
                with with_suppress():
                    await event.wait()
                    event.clear()

                    if task:
                        await cancel(task)

                    if incoming:
                        assert isinstance(nvim.loop, AbstractEventLoop)
                        s, manual = incoming
                        task = nvim.loop.create_task(c0(s, manual=manual))

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


async def _resolve(nvim: Nvim, stack: Stack, user_data: UserData) -> UserData:
    if not user_data.extern:
        return user_data
    else:
        extern, item = user_data.extern
        if extern is not Extern.lsp:
            return user_data
        else:
            comp = stack.lru.get(user_data.uid)
            if comp:
                return replace(
                    user_data,
                    primary_edit=comp.primary_edit,
                    secondary_edits=comp.secondary_edits,
                )
            else:
                done, not_done = await wait(
                    (go(nvim, aw=request(nvim, item=item)),),
                    timeout=stack.settings.clients.lsp.resolve_timeout,
                )
                await cancel(gather(*not_done))
                comp = (await done.pop()) if done else None
                if not comp:
                    return user_data
                else:
                    return replace(
                        user_data,
                        secondary_edits=comp.secondary_edits,
                    )


def _store_inserted(
    nvim: Nvim, unifying_chars: AbstractSet[str], buf: Buffer, edit: Edit
) -> None:
    ns = create_ns(nvim, ns=NS)
    tick: int = buf_get_var(nvim, buf=buf, key="changedtick") or -1
    marks = tuple(buf_get_extmarks(nvim, buf=buf, id=ns))
    if len(marks) == 2:
        m1, m2 = marks
        try:
            text = buf_get_text(nvim, buf=buf, begin=m1.end, end=m2.begin)
            pre = reversed(buf_get_text(nvim, buf=buf, begin=m1.begin, end=m1.end))
        except NvimError as e:
            log.warn("%s", e)
        else:
            if isinstance(edit, RangeEdit):
                prefix = "".join(
                    reversed(
                        tuple(
                            takewhile(
                                lambda c: is_word(c, unifying_chars=unifying_chars),
                                pre,
                            )
                            if is_word(text[:1], unifying_chars=unifying_chars)
                            else takewhile(
                                lambda c: not is_word(c, unifying_chars=unifying_chars),
                                pre,
                            )
                        )
                    )
                )
                rep_text = prefix + text
            else:
                rep_text = text

            rep = Repeat(buf=buf.number, tick=tick, text=rep_text)
            state(repeat=rep)


_DECODER = new_decoder[UserData](UserData)


@rpc(blocking=True)
def _comp_done(nvim: Nvim, stack: Stack, event: Mapping[str, Any]) -> None:
    data = event.get("user_data")
    if data:
        try:
            user_data = _DECODER(data)
        except DecodeError as e:
            log.warn("%s", e)
        else:
            s = state()
            if user_data.change_uid == s.change_id:
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
                    s = state()
                    if user_data.change_uid == s.change_id:
                        ud = await _resolve(nvim, stack=stack, user_data=user_data)

                        def cont() -> None:
                            inserted = edit(nvim, stack=stack, state=s, data=ud)
                            ins = inserted or (-1, -1)
                            if inserted:
                                _store_inserted(
                                    nvim,
                                    unifying_chars=stack.settings.match.unifying_chars,
                                    edit=ud.primary_edit,
                                    buf=buf,
                                )
                            state(inserted=ins, commit_id=uuid4())

                        await async_call(nvim, cont)
                    else:
                        log.warn("%s", "delayed completion")

                go(nvim, aw=cont())


autocmd("CompleteDone") << f"lua {_comp_done.name}(vim.v.completed_item)"
