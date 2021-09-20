from typing import AsyncIterator, cast

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import encode

from ...shared.types import UTF16, Context, ExternLSP, ExternLUA
from ..parse import parse
from ..types import CompletionResponse, LSPcomp
from .request import async_request


async def comp_lsp(
    nvim: Nvim,
    short_name: str,
    weight_adjust: float,
    context: Context,
) -> AsyncIterator[LSPcomp]:
    row, c = context.position
    col = len(encode(context.line_before[:c], encoding=UTF16)) // 2

    async for _, reply in async_request(nvim, "lsp_comp", (row, col)):
        resp = cast(CompletionResponse, reply)
        yield parse(
            ExternLSP, short_name=short_name, weight_adjust=weight_adjust, resp=resp
        )


async def comp_thirdparty(
    nvim: Nvim,
    short_name: str,
    weight_adjust: float,
    context: Context,
) -> AsyncIterator[LSPcomp]:
    async for client, reply in async_request(
        nvim, "lsp_third_party", context.position, context.line
    ):
        name = client or short_name
        resp = cast(CompletionResponse, reply)
        yield parse(ExternLUA, short_name=name, weight_adjust=weight_adjust, resp=resp)
