from typing import Mapping, Optional

from pynvim import Nvim

from ...shared.types import Extern
from ..parse import parse_item
from ..types import Completion
from .request import async_request


async def resolve_lsp(
    nvim: Nvim, extern_type: Extern, item: Mapping
) -> Optional[Completion]:
    stream = async_request(nvim, "lsp_resolve", item)
    async for _, resp in stream:
        comp = parse_item(extern_type, short_name="", weight_adjust=0, item=resp)
        if comp and comp.doc:
            return comp
    else:
        return None
