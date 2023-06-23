from asyncio import Condition
from dataclasses import dataclass
from functools import lru_cache
from itertools import count
from pathlib import Path
from typing import (
    AbstractSet,
    Any,
    AsyncIterator,
    Iterator,
    MutableMapping,
    MutableSequence,
    Optional,
    Sequence,
    Tuple,
)

from pynvim_pp.lib import decode
from pynvim_pp.logging import log
from pynvim_pp.nvim import Nvim
from pynvim_pp.types import NoneType
from std2.pickle.decoder import new_decoder

from ...registry import NAMESPACE, atomic, rpc
from ...server.rt_types import Stack
from ...shared.timeit import timeit


@dataclass(frozen=True)
class _Session:
    uid: int
    done: bool
    acc: MutableSequence[Tuple[Optional[str], Any]]


@dataclass(frozen=True)
class _Payload:
    multipart: bool
    name: str
    method: Optional[str]
    uid: int
    client: Optional[str]
    done: bool
    reply: Any


_LUA = decode((Path(__file__).resolve(strict=True).parent / "lsp.lua").read_bytes())
atomic.exec_lua(_LUA, ())

_STATE: MutableMapping[str, _Session] = {}


_DECODER = new_decoder[_Payload](_Payload)


@lru_cache(maxsize=None)
def _uids(_: str) -> Iterator[int]:
    return count()


@lru_cache(maxsize=None)
def _conds(_: str) -> Condition:
    return Condition()


@rpc(blocking=False)
async def _lsp_push(
    stack: Stack, name: str, client: str, uid: int, acc: Sequence[Any]
) -> None:
    cond = _conds(name)

    async with cond:
        cond.notify_all()


@rpc(blocking=False)
async def _lsp_notify(stack: Stack, rpayload: _Payload) -> None:
    payload = _DECODER(rpayload)
    cond = _conds(payload.name)

    state = _STATE.get(payload.name)
    if not state or payload.uid >= state.uid:
        acc = [
            *(state.acc if state and payload.uid == state.uid else ()),
            (payload.client, payload.reply),
        ]
        _STATE[payload.name] = _Session(uid=payload.uid, done=payload.done, acc=acc)

    async with cond:
        cond.notify_all()


async def async_request(
    name: str, multipart: bool, clients: AbstractSet[str], *args: Any
) -> AsyncIterator[Tuple[Optional[str], Any]]:
    with timeit(f"LSP :: {name}"):
        cond, uid = _conds(name), next(_uids(name))

        _STATE[name] = _Session(uid=uid, done=False, acc=[])

        async with cond:
            cond.notify_all()

        await Nvim.api.exec_lua(
            NoneType,
            f"{NAMESPACE}.{name}(...)",
            (name, multipart, uid, tuple(clients), *args),
        )

        while True:
            if state := _STATE.get(name):
                if state.uid == uid:
                    while state.acc:
                        client, resp = state.acc.pop()
                        yield client, resp
                    if state.done:
                        _STATE.pop(name)
                        break
                elif state.uid > uid:
                    break
                else:
                    log.info(
                        "%s", f"<><> DELAYED LSP RESP <><> :: {name} {state.uid} {uid}"
                    )

            async with cond:
                await cond.wait()
