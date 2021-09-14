from typing import Optional, cast

from pynvim import Nvim

from ...lsp.types import CompletionItem
from ..parse import parse_item
from ..types import Completion
from .request import async_request


async def request(nvim: Nvim, item: CompletionItem) -> Optional[Completion]:
    stream = async_request(nvim, "lsp_preview", item)
    async for _, reply in stream:
        resp = cast(CompletionItem, reply)
        comp = parse_item(True, short_name="", weight_adjust=0, item=resp)
        if comp and comp.doc:
            return comp
    else:
        return None
