from collections import defaultdict
from threading import Condition, Lock
from typing import Any, Iterator, MutableMapping, Sequence, Tuple
from uuid import uuid4

from pynvim.api.nvim import Nvim
from pynvim_pp.lib import threadsafe_call

from ...registry import rpc
from ...server.rt_types import Stack
from ...shared.timeit import timeit

_LOCK = Lock()
_CONDS: MutableMapping[str, Condition] = {}
_STATE: MutableMapping[str, Tuple[str, bool, Sequence[Any]]] = defaultdict(
    lambda: ("", True, ())
)


@rpc(blocking=False)
def _lsp_notify(
    nvim: Nvim, stack: Stack, method: str, session: str, done: bool, reply: Any
) -> None:
    with _LOCK:
        cond = _CONDS.setdefault(session, Condition())
        ses, _, acc = _STATE[method]
        if session == ses:
            _STATE[method] = (session, done, (*acc, reply))
    with cond:
        cond.notify_all()


def blocking_request(nvim: Nvim, method: str, *args: Any) -> Iterator[Any]:
    with timeit(f"LSP :: {method}", force=True):
        session = uuid4().hex
        with _LOCK:
            _STATE[method] = (session, False, ())
            cond = _CONDS.setdefault(session, Condition())
            with cond:
                cond.notify_all()

        def cont() -> None:
            nvim.api.exec_lua(f"{method}(...)", (method, session, *args))

        threadsafe_call(nvim, cont)

        while True:
            with cond:
                cond.wait()
            with _LOCK:
                ses, done, acc = _STATE[method]
            if ses != session:
                break
            else:
                yield from acc
                if done:
                    break

