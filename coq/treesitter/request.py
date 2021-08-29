from asyncio import Condition
from itertools import count
from pathlib import Path
from string import capwords
from typing import AsyncIterator, Iterator, Optional, Sequence, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go

from ..registry import atomic, rpc
from ..server.rt_types import Stack
from ..shared.timeit import timeit
from .types import Payload, RawPayload, SimplePayload, SimpleRawPayload

_UIDS = count()
_COND: Optional[Condition] = None
_SESSION: Tuple[int, bool, Sequence[RawPayload]] = -1, True, ()


_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())


@rpc(blocking=False)
def _ts_notify(nvim: Nvim, stack: Stack, ses: int, reply: Sequence[RawPayload]) -> None:
    async def cont() -> None:
        global _COND, _SESSION
        _COND = _COND or Condition()

        session, _, _ = _SESSION
        if ses == session:
            _SESSION = ses, True, reply

        async with _COND:
            _COND.notify_all()

    go(nvim, aw=cont())


def _parse(load: Optional[SimpleRawPayload]) -> Optional[SimplePayload]:
    if not load:
        return None
    else:
        text = load.get("text", "").encode(errors="ignore").decode()
        if not text:
            return None
        else:
            kind = capwords(load.get("kind", ""), sep=".")
            return SimplePayload(text=text, kind=kind)


def _vaildate(resp: Sequence[RawPayload]) -> Iterator[Payload]:
    for load in resp:
        payload = _parse(load)
        parent = _parse(load.get("parent"))
        grandparent = _parse(load.get("grandparent"))
        if payload:
            yield Payload(
                text=payload.text,
                kind=payload.kind,
                parent=parent,
                grandparent=grandparent,
            )


async def async_request(nvim: Nvim) -> AsyncIterator[Payload]:
    global _COND, _SESSION
    _COND = _COND or Condition()

    with timeit("TS"):
        _SESSION = session, _, _ = next(_UIDS), False, ()

        async with _COND:
            _COND.notify_all()

        def cont() -> None:
            nvim.api.exec_lua("COQts_req(...)", (session,))

        await async_call(nvim, cont)

        while True:
            ses, done, reply = _SESSION
            if ses == session:
                for payload in _vaildate(reply):
                    yield payload
                if done:
                    break
            elif ses > session:
                break

            async with _COND:
                await _COND.wait()
