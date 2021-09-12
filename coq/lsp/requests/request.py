from asyncio import Condition
from collections import defaultdict
from dataclasses import dataclass
from itertools import count
from typing import Any, AsyncIterator, MutableMapping, Optional, Sequence, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go

from ...registry import rpc
from ...server.rt_types import Stack
from ...shared.timeit import timeit


@dataclass(frozen=True)
class _Acc:
    session: int
    done: bool
    acc: Sequence[Tuple[Optional[str], Any]]


_UIDS = count()
_CONDS: MutableMapping[str, Condition] = {}
_STATE: MutableMapping[str, _Acc] = defaultdict(
    lambda: _Acc(session=-1, done=True, acc=())
)


@rpc(blocking=False)
def _lsp_notify(
    nvim: Nvim,
    stack: Stack,
    method: str,
    session: int,
    client: Optional[str],
    done: bool,
    reply: Any,
) -> None:
    async def cont() -> None:
        cond = _CONDS.setdefault(method, Condition())
        acc = _STATE[method]
        if session == acc.session:
            _STATE[method] = _Acc(
                session=session, done=done, acc=(*acc.acc, (client, reply))
            )
        async with cond:
            cond.notify_all()

    go(nvim, aw=cont())


async def async_request(
    nvim: Nvim, method: str, *args: Any
) -> AsyncIterator[Tuple[Optional[str], Any]]:
    with timeit(f"LSP :: {method}"):
        session, done = next(_UIDS), False
        cond = _CONDS.setdefault(method, Condition())

        _STATE[method] = _Acc(session=session, done=done, acc=())
        async with cond:
            cond.notify_all()

        def cont() -> None:
            nvim.api.exec_lua(f"{method}(...)", (method, session, *args))

        await async_call(nvim, cont)

        while True:
            acc = _STATE[method]
            if acc.session == session:
                for client, a in acc.acc:
                    yield client, a
                if done:
                    break
            elif acc.session > session:
                break

            async with cond:
                await cond.wait()
