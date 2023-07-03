from typing import AbstractSet, AsyncIterator, Optional, cast

from ...shared.types import Context, ExternLSP, ExternLUA
from ..parse import parse
from ..types import CompletionResponse, LSPcomp
from .request import async_request


async def comp_lsp(
    short_name: str,
    always_on_top: Optional[AbstractSet[Optional[str]]],
    weight_adjust: float,
    context: Context,
    chunk: int,
    clients: AbstractSet[str],
) -> AsyncIterator[LSPcomp]:
    row, utf8_col = context.position
    lsp_pos = (row, context.utf16_col)
    cursors = (utf8_col, context.utf16_col)

    async for client, reply in async_request("lsp_comp", chunk, clients, lsp_pos):
        resp = cast(CompletionResponse, reply)
        yield parse(
            ExternLSP,
            client=client,
            short_name=short_name,
            cursors=cursors,
            always_on_top=always_on_top,
            weight_adjust=weight_adjust,
            resp=resp,
        )


async def comp_thirdparty(
    short_name: str,
    always_on_top: Optional[AbstractSet[Optional[str]]],
    weight_adjust: float,
    context: Context,
    chunk: int,
    clients: AbstractSet[str],
) -> AsyncIterator[LSPcomp]:
    _, utf8_col = context.position
    cursors = (utf8_col, context.utf16_col)

    async for client, reply in async_request(
        "lsp_third_party", chunk, clients, context.position, context.line
    ):
        name = client or short_name
        resp = cast(CompletionResponse, reply)
        yield parse(
            ExternLUA,
            client=client,
            short_name=name,
            cursors=cursors,
            always_on_top=always_on_top,
            weight_adjust=weight_adjust,
            resp=resp,
        )
