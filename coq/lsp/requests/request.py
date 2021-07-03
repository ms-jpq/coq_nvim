from threading import Event, Lock
from typing import Any, Iterator, MutableMapping, MutableSequence, Tuple
from uuid import uuid4

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import threadsafe_call

from ...registry import rpc
from ...server.rt_types import Stack

_LOCK = Lock()
_EVENTS: MutableMapping[str, Event]
_STATE: MutableMapping[str, Tuple[str, MutableSequence[Any]]] = {}


@rpc(blocking=False)
def _lsp_notify(
    nvim: Nvim, stack: Stack, method: str, session: str, reply: Any
) -> None:
    with _LOCK:
        ev = _EVENTS.get(method, Event())
        ses, acc = _STATE.get(method, ("", []))
        if session == ses:
            acc.append(reply)
            ev.set()


def blocking_request(nvim: Nvim, method: str, *args: Any) -> Iterator[Any]:
    session = uuid4().hex
    with _LOCK:
        ev = _EVENTS.setdefault(method, Event())
        _STATE[method] = (session, [])

    def cont() -> None:
        nvim.api.exec_lua(f"{method}(...)", (method, session, *args))

    threadsafe_call(nvim, cont)

    while True:
        ev.wait()
        with _LOCK:
            ses, acc = _STATE.get(method, ("", []))
            if ses != session:
                break
            else:
                now = tuple(acc)
                acc.clear()
                yield from now

