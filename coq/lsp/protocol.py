from asyncio.tasks import create_task
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Awaitable, Mapping, Optional, cast

from pynvim_pp.lib import decode
from pynvim_pp.nvim import Nvim
from pynvim_pp.types import NoneType
from std2.pickle.decoder import new_decoder

_LUA = decode(
    (Path(__file__).resolve(strict=True).parent / "protocol.lua").read_bytes()
)


@dataclass(frozen=True)
class LSProtocol:
    CompletionItemKind: Mapping[Optional[int], str]
    InsertTextFormat: Mapping[Optional[int], str]


@lru_cache(maxsize=None)
def protocol() -> Awaitable[LSProtocol]:
    async def cont() -> LSProtocol:
        raw: Mapping[str, Mapping[str, int]] = await cast(
            Any, Nvim.api.exec_lua(NoneType, _LUA, ())
        )
        trans = {key: {v: k for k, v in val.items()} for key, val in raw.items()}
        protocol = new_decoder[LSProtocol](LSProtocol, strict=False)(trans)
        return protocol

    return create_task(cont())
