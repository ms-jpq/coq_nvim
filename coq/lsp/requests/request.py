from collections import defaultdict
from threading import Event, Lock
from typing import Any, Iterator, MutableMapping, Optional, Sequence, Tuple
from uuid import uuid4

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import threadsafe_call

from ...registry import rpc
from ...server.rt_types import Stack

_LOCK = Lock()
_STATE: MutableMapping[str, Tuple[Event, str, bool, Sequence[Any]]] = defaultdict(
    lambda: (Event(), "", True, ())
)


@rpc(blocking=False)
def _lsp_notify(
    nvim: Nvim,
    stack: Stack,
    method: str,
    session: str,
    done: bool,
    client: Optional[str],
    reply: Any,
) -> None:
    with _LOCK:
        ev, ses, _, acc = _STATE[method]
        if session == ses:
            _STATE[method] = (ev, session, done, (*acc, reply))
            ev.set()


def blocking_request(nvim: Nvim, method: str, *args: Any) -> Iterator[Any]:
    ev, session = Event(), uuid4().hex
    with _LOCK:
        prev, _, __, ___ = _STATE[method]
        _STATE[method] = (ev, session, False, ())
        prev.set()

    def cont() -> None:
        nvim.api.exec_lua(f"{method}(...)", (method, session, *args))

    threadsafe_call(nvim, cont)

    while True:
        ev.wait()
        with _LOCK:
            ____, ses, done, acc = _STATE[method]
        if ses != session:
            break
        else:
            yield from acc
            if done:
                break

