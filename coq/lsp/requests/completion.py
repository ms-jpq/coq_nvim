from typing import Any, AsyncIterator, Mapping, Sized, cast

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import encode
from pynvim_pp.logging import log
from std2.types import is_iterable_not_str

from ...consts import DEBUG
from ...shared.types import UTF16, Context
from ..parse import parse
from ..types import CompletionResponse, LSPcomp
from .request import async_request


async def request_lsp(
    nvim: Nvim,
    short_name: str,
    weight_adjust: float,
    context: Context,
) -> AsyncIterator[LSPcomp]:
    row, c = context.position
    col = len(encode(context.line_before[:c], encoding=UTF16)) // 2

    async for client, reply in async_request(nvim, "lsp_comp", (row, col)):
        resp = cast(CompletionResponse, reply)
        if DEBUG:
            if isinstance(resp, Mapping):
                thing: Any = len(resp.get("items") or ())
            elif isinstance(resp, Sized) and is_iterable_not_str(resp):
                thing = len(resp)
            else:
                thing = resp
            msg = f"LSP !! {client} {thing}"
            log.info("%s", msg)
        yield parse(True, short_name=short_name, weight_adjust=weight_adjust, resp=resp)


async def request_thirdparty(
    nvim: Nvim,
    short_name: str,
    weight_adjust: float,
    context: Context,
) -> AsyncIterator[LSPcomp]:
    async for client, reply in async_request(nvim, "lsp_third_party", context.position):
        name = client or short_name
        resp = cast(CompletionResponse, reply)
        yield parse(False, short_name=name, weight_adjust=weight_adjust, resp=resp)
