from typing import AbstractSet, AsyncIterator, Optional, cast

from ...shared.types import Context, ExternLSP, ExternLUA
from ..parse import parse
from ..protocol import protocol
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
    pc = await protocol()

    async for client in async_request("lsp_comp", chunk, clients, context.cursor):
        resp = cast(CompletionResponse, client.message)
        yield parse(
            pc,
            extern_type=ExternLSP,
            client=client.name,
            encoding=client.offset_encoding,
            short_name=short_name,
            cursors=context.cursor,
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
    pc = await protocol()

    async for client in async_request(
        "lsp_third_party", chunk, clients, context.cursor, context.line
    ):
        name = client.name or short_name
        resp = cast(CompletionResponse, client.message)
        yield parse(
            pc,
            extern_type=ExternLUA,
            client=client.name,
            encoding=client.offset_encoding,
            short_name=name,
            cursors=context.cursor,
            always_on_top=always_on_top,
            weight_adjust=weight_adjust,
            resp=resp,
        )
