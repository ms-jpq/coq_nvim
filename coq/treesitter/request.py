from asyncio import Condition
from dataclasses import dataclass
from itertools import count
from pathlib import Path
from string import capwords
from typing import Iterator, Optional, Sequence, Tuple

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go, recode

from ..registry import NAMESPACE, atomic, rpc
from ..server.rt_types import Stack
from ..shared.timeit import timeit
from .types import Payload, RawPayload, SimplePayload, SimpleRawPayload


@dataclass(frozen=True)
class _Session:
    uid: int
    done: bool
    payloads: Sequence[RawPayload]
    elapsed: float


_UIDS = count()
_COND: Optional[Condition] = None
_SESSION = _Session(uid=-1, done=True, payloads=(), elapsed=0)


_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())


@rpc(blocking=False)
def _ts_notify(
    nvim: Nvim, stack: Stack, session: int, reply: Sequence[RawPayload], elapsed: float
) -> None:
    async def cont() -> None:
        global _COND, _SESSION
        _COND = _COND or Condition()

        if session >= _SESSION.uid:
            _SESSION = _Session(uid=session, done=True, payloads=reply, elapsed=elapsed)

        async with _COND:
            _COND.notify_all()

    go(nvim, aw=cont())


def _parse(load: Optional[SimpleRawPayload]) -> Optional[SimplePayload]:
    if not load:
        return None
    else:
        text = recode(load.get("text", ""))
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


async def async_request(
    nvim: Nvim, lines_around: int
) -> Tuple[Iterator[Payload], float]:
    global _COND, _SESSION
    _COND = _COND or Condition()

    with timeit("TS"):
        uid = next(_UIDS)
        _SESSION = _Session(uid=uid, done=False, payloads=(), elapsed=0)

        async with _COND:
            _COND.notify_all()

        def cont() -> None:
            nvim.api.exec_lua("COQts_req(...)", (uid, lines_around))

        await async_call(nvim, cont)

        while True:
            if _SESSION.uid == uid and _SESSION.done:
                return _vaildate(_SESSION.payloads), _SESSION.elapsed

            elif _SESSION.uid > uid:
                return iter(()), -1

            else:
                async with _COND:
                    await _COND.wait()
