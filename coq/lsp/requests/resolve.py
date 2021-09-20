from typing import Mapping, Optional, Type

from pynvim import Nvim

from ...shared.types import ExternLSP
from ..parse import parse_item
from ..types import Completion
from .request import async_request


async def resolve(
    nvim: Nvim, extern_type: Type[ExternLSP], item: Mapping
) -> Optional[Completion]:
    if extern_type is ExternLSP:
        stream = async_request(nvim, "lsp_resolve", item)
        async for _, resp in stream:
            comp = parse_item(ExternLSP, short_name="", weight_adjust=0, item=resp)
            if comp and comp.doc:
                return comp
        else:
            return None
