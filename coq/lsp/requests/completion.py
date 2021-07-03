from pathlib import Path
from typing import Sequence, Tuple, Iterator

from pynvim.api.nvim import Nvim
from pynvim_pp.logging import log
from std2.pickle import DecodeError, new_decoder

from ...registry import atomic
from ...shared.timeit import timeit
from ...shared.types import UTF16, Completion, Context
from ..parse import parse
from ..types import CompletionResponse
from .request import blocking_request

_LUA = (Path(__file__).resolve().parent / "completion.lua").read_text("UTF-8")

atomic.exec_lua(_LUA, ())

_DECODER = new_decoder(CompletionResponse, strict=False)


def request(
    nvim: Nvim,
    short_name: str,
    tie_breaker: int,
    context: Context,
) -> Iterator[Tuple[bool, Sequence[Completion]]]:

    row, c = context.position
    col = len(context.line_before[:c].encode(UTF16)) // 2

    for reply in blocking_request(nvim, "COQlsp_comp", (row, col)):
        try:
            with timeit("LSP :: DECODE"):
                resp: CompletionResponse = _DECODER(reply)
        except DecodeError as e:
            log.warn("%s", e)
            yield False, ()
        else:
            incomplete, comps = parse(short_name, tie_breaker=tie_breaker, resp=resp)
            use_cache = not incomplete
            yield use_cache, comps

