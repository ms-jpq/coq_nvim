from asyncio import Condition, sleep
from itertools import count
from pathlib import Path
from string import capwords
from typing import AsyncIterator, Optional, Sequence, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go

from ..registry import atomic, rpc
from ..server.rt_types import Stack
from ..shared.timeit import timeit
from .types import Payload

_UIDS = count()
_COND: Optional[Condition] = None
_SESSION: Tuple[int, Sequence[Payload]] = -1, ()


_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())


@rpc(blocking=False)
def _ts_notify(nvim: Nvim, stack: Stack, ses: int, reply: Sequence[Payload]) -> None:
    async def cont() -> None:
        global _COND, _SESSION
        _COND = _COND or Condition()

        session, _ = _SESSION
        if ses == session:
            _SESSION = ses, reply

        async with _COND:
            _COND.notify_all()

    go(nvim, aw=cont())


async def _vaildate(resp: Sequence[Payload]) -> AsyncIterator[Payload]:
    for payload in resp:
        text = payload["text"].encode(errors="ignore").decode()
        kind = capwords(payload["kind"])
        yield Payload(text=text, kind=kind)


async def async_request(nvim: Nvim) -> AsyncIterator[Payload]:
    global _COND, _SESSION
    _COND = _COND or Condition()

    with timeit("TS"):
        _SESSION = session, _ = next(_UIDS), ()

        async with _COND:
            _COND.notify_all()
        await sleep(0)

        def cont() -> None:
            nvim.api.exec_lua("COQts_req(...)", (session,))

        await async_call(nvim, cont)

        while True:
            ses, reply = _SESSION
            if ses == session:
                async for payload in _vaildate(reply):
                    yield payload
                break
            elif ses > session:
                break

            async with _COND:
                await _COND.wait()

