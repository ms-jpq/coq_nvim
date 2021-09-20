from typing import Optional

from pynvim import Nvim

from ...shared.types import ExternLSP, ExternLUA
from ..parse import parse_item
from ..types import Completion
from .request import async_request


async def resolve(nvim: Nvim, extern: ExternLSP) -> Optional[Completion]:
    if isinstance(extern, ExternLUA):
        return None
    else:
        stream = async_request(nvim, "lsp_resolve", extern.item)
        async for _, resp in stream:
            comp = parse_item(ExternLSP, short_name="", weight_adjust=0, item=resp)
            if comp and comp.doc:
                return comp
        else:
            return None
