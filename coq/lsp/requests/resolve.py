from typing import MutableSequence, Optional

from ...shared.types import Completion, ExternLSP, ExternLUA
from ..parse import parse_item
from ..protocol import protocol
from .request import async_request


async def resolve(extern: ExternLSP) -> Optional[Completion]:
    name = "lsp_third_party_resolve" if isinstance(extern, ExternLUA) else "lsp_resolve"
    comps: MutableSequence[Completion] = []

    clients = {extern.client} if extern.client else set()
    pc = await protocol()

    async for client in async_request(name, None, clients, extern.item):
        comp = parse_item(
            pc,
            extern_type=type(extern),
            client=client.name,
            encoding=client.offset_encoding,
            short_name="",
            cursors=(-1, -1, -1, -1),
            always_on_top=None,
            weight_adjust=0,
            item=client.message,
        )
        if extern.client and client.name == extern.client:
            return comp
        elif comp:
            comps.append(comp)
    else:
        for comp in comps:
            if comp.doc:
                return comp
        else:
            return None
