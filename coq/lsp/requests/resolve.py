from typing import Optional

from pynvim import Nvim

from ...shared.types import ExternLSP, ExternLUA
from ..parse import parse_item
from ..types import Completion
from .request import async_request


async def resolve(nvim: Nvim, extern: ExternLSP) -> Optional[Completion]:
    name = "lsp_third_party_resolve" if isinstance(extern, ExternLUA) else "lsp_resolve"

    async for _, resp in async_request(nvim, name, extern.item):
        comp = parse_item(type(extern), short_name="", weight_adjust=0, item=resp)
        if comp and comp.doc:
            return comp
    else:
        return None
