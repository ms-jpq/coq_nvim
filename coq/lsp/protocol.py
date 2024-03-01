from asyncio import wrap_future
from asyncio.tasks import create_task
from concurrent.futures import Future, InvalidStateError
from contextlib import suppress
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Mapping, Optional, cast

from pynvim_pp.lib import decode
from pynvim_pp.nvim import Nvim
from pynvim_pp.types import NoneType
from std2.pickle.decoder import new_decoder

_LUA = decode(
    Path(__file__).resolve(strict=True).with_name("protocol.lua").read_bytes()
)


@dataclass(frozen=True)
class LSProtocol:
    CompletionItemKind: Mapping[Optional[int], str]
    InsertTextFormat: Mapping[Optional[int], str]


@lru_cache(maxsize=None)
def _protocol() -> Future:
    async def c1() -> LSProtocol:
        raw: Mapping[str, Mapping[str, int]] = await cast(
            Any, Nvim.api.exec_lua(NoneType, _LUA, ())
        )
        trans = {key: {v: k for k, v in val.items()} for key, val in raw.items()}
        protocol = new_decoder[LSProtocol](LSProtocol, strict=False)(trans)
        return protocol

    f: Future = Future()

    async def c2() -> None:
        try:
            ret = await c1()
        except BaseException as e:
            with suppress(InvalidStateError):
                f.set_exception(e)
        else:
            with suppress(InvalidStateError):
                f.set_result(ret)

    create_task(c2())
    return f


async def protocol() -> LSProtocol:
    f: Future = _protocol()
    return await wrap_future(f)
