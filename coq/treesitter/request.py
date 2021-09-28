from asyncio import Condition
from dataclasses import dataclass
from itertools import count
from pathlib import Path
from string import capwords
from typing import Generic, Iterable, Iterator, Optional, Sequence, TypeVar

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go, recode

from ..registry import NAMESPACE, atomic, rpc
from ..server.rt_types import Stack
from ..shared.timeit import timeit
from .types import Payload, RawPayload, SimplePayload, SimpleRawPayload

_T = TypeVar("_T")


@dataclass(frozen=True)
class _Payload(Generic[_T]):
    buf: int
    filetype: str
    payloads: Iterable[_T]
    elapsed: float


@dataclass(frozen=True)
class _Session:
    uid: int
    done: bool
    payload: _Payload


_UIDS = count()
_COND: Optional[Condition] = None
_NIL_P = _Payload[RawPayload](buf=-1, filetype="", payloads=(), elapsed=-1)
_SESSION = _Session(uid=-1, done=True, payload=_NIL_P)


_LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())


@rpc(blocking=False)
def _ts_notify(
    nvim: Nvim,
    stack: Stack,
    session: int,
    buf: int,
    filetype: str,
    reply: Sequence[RawPayload],
    elapsed: float,
) -> None:
    async def cont() -> None:
        global _COND, _SESSION
        _COND = _COND or Condition()

        if session >= _SESSION.uid:
            payload = _Payload(
                buf=buf,
                filetype=filetype,
                payloads=reply,
                elapsed=elapsed,
            )
            _SESSION = _Session(uid=session, done=True, payload=payload)

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


def _vaildate(r_playload: _Payload[RawPayload]) -> _Payload[Payload]:
    def cont() -> Iterator[Payload]:
        for load in r_playload.payloads:
            if filename := load.get("filename"):
                if payload := _parse(load):
                    parent = _parse(load.get("parent"))
                    grandparent = _parse(load.get("grandparent"))
                    yield Payload(
                        filename=filename,
                        text=payload.text,
                        kind=payload.kind,
                        parent=parent,
                        grandparent=grandparent,
                    )

    payload = _Payload(
        buf=r_playload.buf,
        filetype=r_playload.filetype,
        elapsed=r_playload.elapsed,
        payloads=cont(),
    )
    return payload


async def async_request(nvim: Nvim, lines_around: int) -> Optional[_Payload[Payload]]:
    global _COND, _SESSION
    _COND = _COND or Condition()

    with timeit("TS"):
        uid = next(_UIDS)
        _SESSION = _Session(uid=uid, done=False, payload=_NIL_P)

        async with _COND:
            _COND.notify_all()

        def cont() -> None:
            nvim.api.exec_lua(f"{NAMESPACE}.ts_req(...)", (uid, lines_around))

        await async_call(nvim, cont)

        while True:
            if _SESSION.uid == uid and _SESSION.done:
                return _vaildate(_SESSION.payload)

            elif _SESSION.uid > uid:
                return None

            else:
                async with _COND:
                    await _COND.wait()
