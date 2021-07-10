from asyncio import Condition, sleep
from pathlib import Path
from typing import Sequence, Tuple
from uuid import uuid4

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go

from ..registry import atomic, rpc
from ..server.rt_types import Stack
from ..shared.timeit import timeit
from .types import Payload

_COND = Condition()
_SESSION: Tuple[str, Sequence[Payload]] = uuid4().hex, ()


_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())


@rpc(blocking=False)
def _ts_notify(nvim: Nvim, stack: Stack, ses: str, reply: Sequence[Payload]) -> None:
    async def cont() -> None:
        global _SESSION
        session, _ = _SESSION
        if ses == session:
            _SESSION = ses, reply

        async with _COND:
            _COND.notify_all()

    go(nvim, aw=cont())


async def async_request(nvim: Nvim) -> Sequence[Payload]:
    global _SESSION

    with timeit(f"TS"):
        _SESSION = session, _ = uuid4().hex, ()

        async with _COND:
            _COND.notify_all()
        await sleep(0)

        def cont() -> None:
            nvim.api.exec_lua("TSreq(...)", ())

        await async_call(nvim, cont)

        while True:
            async with _COND:
                await _COND.wait()
            ses, reply = _SESSION
            if ses != session:
                return ()
            else:
                return reply

