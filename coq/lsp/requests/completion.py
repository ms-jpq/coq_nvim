from concurrent.futures import CancelledError, Future, InvalidStateError
from contextlib import suppress
from pathlib import Path
from threading import Lock
from typing import Any, Iterator, Sequence, Tuple
from uuid import UUID, uuid4

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import threadsafe_call

from ...registry import rpc
from ...server.runtime import Stack
from ...shared.types import UTF16, Completion, Context, WTF8Pos
from ..parse import parse
from ..protocol import LSProtocol

LUA = (Path(__file__).resolve().parent / "request.lua").read_text("UTF-8")

_LOCK = Lock()
_CUR: Tuple[UUID, Future] = uuid4(), Future()


def _request(nvim: Nvim, session: UUID, pos: WTF8Pos) -> Any:
    global _CUR
    with _LOCK:
        _, fut = _CUR
        fut.cancel()
        _CUR = token, fut = uuid4(), Future()

    def cont() -> None:
        args = (str(token), str(session), pos)
        nvim.api.exec_lua("COQlsp_req(...)", args)

    threadsafe_call(nvim, cont)

    try:
        ret = fut.result()
    except CancelledError:
        ret = None

    return ret


def request(
    nvim: Nvim,
    short_name: str,
    tie_breaker: int,
    protocol: LSProtocol,
    context: Context,
) -> Iterator[Sequence[Completion]]:
    session = uuid4()
    row, c = context.position
    col = len(context.line_before[:c].encode(UTF16)) // 2

    go = True
    while go:
        reply = _request(nvim, session=session, pos=(row, col))
        go, comps = parse(
            short_name, tie_breaker=tie_breaker, client=protocol, reply=reply
        )
        yield comps


@rpc(blocking=True)
def _lsp_comp_notify(
    nvim: Nvim, stack: Stack, args: Tuple[UUID, Sequence[Any]]
) -> None:
    token, msg = args

    with _LOCK:
        c_token, fut = _CUR

    if token == c_token:
        reply, *_ = msg
        with suppress(InvalidStateError):
            fut.set_result(reply)

