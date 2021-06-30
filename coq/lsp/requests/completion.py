from pathlib import Path
from typing import Iterator, Sequence
from uuid import uuid4

from pynvim.api.nvim import Nvim
from pynvim_pp.logging import log
from std2.pickle import DecodeError, decode

from ...registry import atomic
from ...shared.types import UTF16, Completion, Context
from ..parse import parse
from ..types import CompletionResponse
from .request import blocking_request

_LUA = (Path(__file__).resolve().parent / "completion.lua").read_text("UTF-8")

atomic.exec_lua(_LUA, ())


def request(
    nvim: Nvim,
    short_name: str,
    tie_breaker: int,
    context: Context,
) -> Iterator[Sequence[Completion]]:
    session = uuid4()
    row, c = context.position
    col = len(context.line_before[:c].encode(UTF16)) // 2

    reply = blocking_request(nvim, "COQlsp_comp", str(session), (row, col))
    try:
        resp: CompletionResponse = decode(CompletionResponse, reply, strict=False)
    except DecodeError as e:
        log.warn("%s", e)
    else:
        comps = parse(short_name, tie_breaker=tie_breaker, resp=resp)
        yield comps

