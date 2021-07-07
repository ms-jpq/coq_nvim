from asyncio import Condition
from collections import defaultdict
from typing import Any, AsyncIterator, MutableMapping, Sequence, Tuple
from uuid import uuid4

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go

from ...registry import rpc
from ...server.rt_types import Stack
from ...shared.timeit import timeit

_CONDS: MutableMapping[str, Condition] = {}
_STATE: MutableMapping[str, Tuple[str, bool, Sequence[Any]]] = defaultdict(
    lambda: ("", True, ())
)


@rpc(blocking=False)
def _lsp_notify(
    nvim: Nvim, stack: Stack, method: str, session: str, done: bool, reply: Any
) -> None:
    async def cont() -> None:
        cond = _CONDS.setdefault(session, Condition())
        ses, _, acc = _STATE[method]
        if session == ses:
            _STATE[method] = (session, done, (*acc, reply))
        async with cond:
            cond.notify_all()

    go(cont())


async def async_request(nvim: Nvim, method: str, *args: Any) -> AsyncIterator[Any]:
    with timeit(f"LSP :: {method}", force=True):
        session = uuid4().hex
        _STATE[method] = (session, False, ())
        cond = _CONDS.setdefault(session, Condition())
        async with cond:
            cond.notify_all()

        def cont() -> None:
            nvim.api.exec_lua(f"{method}(...)", (method, session, *args))

        await async_call(nvim, cont)

        done = False
        while not done:
            async with cond:
                await cond.wait()
            ses, done, acc = _STATE[method]
            if ses != session:
                break
            else:
                for a in acc:
                    yield a

