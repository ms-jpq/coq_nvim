from typing import Optional, cast

from pynvim import Nvim

from ...lsp.types import CompletionItem
from ..parse import parse_item
from ..types import Completion
from .request import async_request


async def request(nvim: Nvim, item: CompletionItem) -> Optional[Completion]:
    stream = async_request(nvim, "COQlsp_preview", item)
    async for _, reply in stream:
        if reply:
            break
    else:
        reply = None

    if reply:
        resp = cast(CompletionItem, reply)
        return parse_item("", weight_adjust=0, item=resp)
    else:
        return None
