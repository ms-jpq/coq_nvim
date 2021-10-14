from typing import Optional

from pynvim import Nvim

from ...shared.types import ExternLSP, ExternLUA
from ..parse import parse_item
from ..types import Completion
from .request import async_request


async def resolve(nvim: Nvim, extern: ExternLSP) -> Optional[Completion]:
    name = "lsp_third_party_resolve" if isinstance(extern, ExternLUA) else "lsp_resolve"

    async for client, resp in async_request(nvim, name, extern.item):
        if client == extern.client:
            comp = parse_item(
                type(extern),
                client=client,
                short_name="",
                weight_adjust=0,
                item=resp,
            )
            return comp
    else:
        return None
