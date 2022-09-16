from asyncio import Condition
from dataclasses import dataclass
from functools import lru_cache
from itertools import count
from pathlib import Path
from string import capwords
from typing import Generic, Iterable, Iterator, Optional, Sequence, TypeVar

from pynvim_pp.lib import recode
from pynvim_pp.nvim import Nvim
from pynvim_pp.types import NoneType
from std2.cell import RefCell

from ..registry import NAMESPACE, atomic, rpc
from ..server.rt_types import Stack
from ..shared.timeit import timeit
from .types import Payload, RawPayload, SimplePayload, SimpleRawPayload

_T = TypeVar("_T")


@dataclass(frozen=True)
class _Payload(Generic[_T]):
    buf: int
    lo: int
    hi: int
    filetype: str
    filename: str
    payloads: Iterable[_T]
    elapsed: float


@dataclass(frozen=True)
class _Session:
    uid: int
    done: bool
    payload: _Payload


_LUA = (Path(__file__).resolve(strict=True).parent / "request.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())

_UIDS = count()
_NIL_P = _Payload[RawPayload](
    buf=-1, lo=-1, hi=-1, filetype="", filename="", payloads=(), elapsed=-1
)
_CELL = RefCell(_Session(uid=-1, done=True, payload=_NIL_P))


@lru_cache(maxsize=None)
def _cond() -> Condition:
    return Condition()


@rpc(blocking=False)
async def _ts_notify(
    stack: Stack,
    session: int,
    buf: int,
    lo: int,
    hi: int,
    filetype: str,
    filename: str,
    reply: Sequence[RawPayload],
    elapsed: float,
) -> None:
    cond = _cond()

    if session >= _CELL.val.uid:
        payload = _Payload(
            buf=buf,
            lo=lo,
            hi=hi,
            filetype=filetype,
            filename=filename,
            payloads=reply,
            elapsed=elapsed,
        )
        _CELL.val = _Session(uid=session, done=True, payload=payload)

    async with cond:
        cond.notify_all()


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
            if payload := _parse(load):
                range = load.get("range")
                assert range
                parent = _parse(load.get("parent"))
                grandparent = _parse(load.get("grandparent"))
                yield Payload(
                    filename="",
                    range=range,
                    text=payload.text,
                    kind=payload.kind,
                    parent=parent,
                    grandparent=grandparent,
                )

    payload = _Payload(
        buf=r_playload.buf,
        lo=r_playload.lo,
        hi=r_playload.hi,
        filetype=r_playload.filetype,
        filename=r_playload.filename,
        elapsed=r_playload.elapsed,
        payloads=cont(),
    )
    return payload


async def async_request() -> Optional[_Payload[Payload]]:
    cond = _cond()

    with timeit("TS"):
        uid = next(_UIDS)
        _CELL.val = _Session(uid=uid, done=False, payload=_NIL_P)

        async with cond:
            cond.notify_all()

        await Nvim.api.exec_lua(NoneType, f"{NAMESPACE}.ts_req(...)", (uid,))

        while True:
            session = _CELL.val
            if session.uid == uid and session.done:
                return _vaildate(session.payload)

            elif session.uid > uid:
                return None

            else:
                async with _cond():
                    await _cond().wait()
