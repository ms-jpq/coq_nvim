from concurrent.futures import CancelledError, Future, InvalidStateError
from contextlib import suppress
from threading import Lock
from typing import Any, MutableMapping

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import threadsafe_call

from ...registry import rpc
from ...server.rt_types import Stack

_LOCK = Lock()
_FUTS: MutableMapping[str, Future] = {}


@rpc(blocking=False)
def _lsp_notify(nvim: Nvim, stack: Stack, method: str, reply: Any) -> None:
    with _LOCK:
        fut = _FUTS[method]
    with suppress(InvalidStateError):
        fut.set_result(reply)


def blocking_request(nvim: Nvim, method: str, *args: Any) -> Any:
    with _LOCK:
        prev = _FUTS.get(method)
        if prev:
            prev.cancel()
        fut = _FUTS[method] = Future()

    def cont() -> None:
        nvim.api.exec_lua(f"{method}(...)", (method, *args))

    threadsafe_call(nvim, cont)

    try:
        ret = fut.result()
    except CancelledError:
        ret = None

    return ret

