from asyncio import Condition, sleep
from collections import defaultdict
from itertools import count
from typing import Any, AsyncIterator, MutableMapping, Sequence, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go

from ...registry import rpc
from ...server.rt_types import Stack
from ...shared.timeit import timeit

_UIDS = count()
_CONDS: MutableMapping[str, Condition] = {}
_STATE: MutableMapping[str, Tuple[int, bool, Sequence[Any]]] = defaultdict(
    lambda: (-1, True, ())
)


@rpc(blocking=False)
def _lsp_notify(
    nvim: Nvim, stack: Stack, method: str, ses: int, done: bool, reply: Any
) -> None:
    async def cont() -> None:
        cond = _CONDS.setdefault(method, Condition())
        session, _, acc = _STATE[method]
        if ses == session:
            _STATE[method] = (ses, done, (*acc, reply))
        async with cond:
            cond.notify_all()

    go(nvim, aw=cont())


async def async_request(nvim: Nvim, method: str, *args: Any) -> AsyncIterator[Any]:
    with timeit(f"LSP :: {method}"):
        session, done = next(_UIDS), False
        cond = _CONDS.setdefault(method, Condition())

        _STATE[method] = (session, done, ())
        async with cond:
            cond.notify_all()
        await sleep(0)

        def cont() -> None:
            nvim.api.exec_lua(f"{method}(...)", (method, session, *args))

        await async_call(nvim, cont)

        while not done:
            ses, done, acc = _STATE[method]
            if ses == session:
                for a in acc:
                    yield a
            elif ses > session:
                break
            else:
                async with cond:
                    await cond.wait()

