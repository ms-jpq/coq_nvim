from asyncio import Condition
from collections import defaultdict
from dataclasses import dataclass
from itertools import count
from pathlib import Path
from typing import (
    AbstractSet,
    Any,
    AsyncIterator,
    MutableMapping,
    Optional,
    Sequence,
    Tuple,
)

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import async_call, go
from std2.pickle import new_decoder

from ...registry import NAMESPACE, atomic, rpc
from ...server.rt_types import Stack
from ...shared.timeit import timeit


@dataclass(frozen=True)
class _Session:
    uid: int
    done: bool
    acc: Sequence[Tuple[Optional[str], Any]]


@dataclass(frozen=True)
class _Payload:
    name: str
    method: Optional[str]
    uid: int
    client: Optional[str]
    done: bool
    reply: Any


_LUA = (Path(__file__).resolve(strict=True).parent / "lsp.lua").read_text("UTF-8")
atomic.exec_lua(_LUA, ())

_UIDS = count()
_CONDS: MutableMapping[str, Condition] = {}
_STATE: MutableMapping[str, _Session] = defaultdict(
    lambda: _Session(uid=-1, done=True, acc=())
)


_DECODER = new_decoder[_Payload](_Payload)


@rpc(blocking=False)
def _lsp_notify(nvim: Nvim, stack: Stack, rpayload: _Payload) -> None:
    async def cont() -> None:
        payload = _DECODER(rpayload)
        cond = _CONDS.setdefault(payload.name, Condition())

        acc = _STATE[payload.name]
        if payload.uid >= acc.uid:
            _STATE[payload.name] = _Session(
                uid=payload.uid,
                done=payload.done,
                acc=(*acc.acc, (payload.client, payload.reply)),
            )
        async with cond:
            cond.notify_all()

    go(nvim, aw=cont())


async def async_request(
    nvim: Nvim, name: str, clients: AbstractSet[str], *args: Any
) -> AsyncIterator[Tuple[Optional[str], Any]]:
    with timeit(f"LSP :: {name}"):
        cond = _CONDS.setdefault(name, Condition())

        uid = next(_UIDS)
        _STATE[name] = _Session(uid=uid, done=False, acc=())
        async with cond:
            cond.notify_all()

        def cont() -> None:
            nvim.api.exec_lua(
                f"{NAMESPACE}.{name}(...)",
                (name, uid, tuple(clients), *args),
            )

        await async_call(nvim, cont)

        while True:
            acc = _STATE[name]
            if acc.uid == uid:
                _STATE[name] = _Session(uid=acc.uid, done=acc.done, acc=())
                for client, a in acc.acc:
                    yield client, a
                if acc.done:
                    break
            elif acc.uid > uid:
                break

            async with cond:
                await cond.wait()
