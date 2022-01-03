from asyncio.events import AbstractEventLoop
from concurrent.futures import Executor
from logging import DEBUG as DEBUG_LV
from logging import INFO
from queue import SimpleQueue
from string import Template
from textwrap import dedent
from typing import Any, MutableMapping, Optional, cast

from pynvim import Nvim
from pynvim_pp.client import Client
from pynvim_pp.lib import threadsafe_call, write
from pynvim_pp.logging import log, with_suppress
from pynvim_pp.rpc import RpcCallable, RpcMsg, nil_handler
from std2.functools import constantly
from std2.pickle.types import DecodeError
from std2.types import AnyFun

from ._registry import ____
from .consts import DEBUG, DEBUG_DB, DEBUG_METRICS, TMP_DIR
from .registry import atomic, autocmd, rpc
from .server.registrants.attachment import BUF_EVENTS
from .server.registrants.options import set_options
from .server.rt_types import Stack, ValidationError
from .server.runtime import stack
from .shared.timeit import timeit

_FN = constantly(None)


def _set_debug() -> None:
    if DEBUG or DEBUG_METRICS or DEBUG_DB:
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        log.setLevel(DEBUG_LV)
    else:
        log.setLevel(INFO)


class CoqClient(Client):
    def __init__(self, pool: Executor) -> None:
        self._pool = pool
        self._handlers: MutableMapping[str, RpcCallable] = {}
        self._event_queue: SimpleQueue = SimpleQueue()
        self._stack: Optional[Stack] = None

        _set_debug()

    def _handle(self, nvim: Nvim, msg: RpcMsg) -> Any:
        name, args = msg
        if name.startswith("nvim_buf_"):
            handler = cast(AnyFun[None], BUF_EVENTS.get(name, _FN))
            return handler(nvim, self._stack, *args)
        else:
            handler = cast(AnyFun[None], self._handlers.get(name, nil_handler(name)))
            return handler(nvim, self._stack, *args)

    def on_msg(self, nvim: Nvim, msg: RpcMsg) -> Any:
        name, _ = msg
        if not self._stack:
            self._event_queue.put(msg)
            return None
        else:
            with timeit(f"<> {name}"):
                return self._handle(nvim, msg)

    def wait(self, nvim: Nvim) -> int:
        assert isinstance(nvim.loop, AbstractEventLoop)
        nvim.loop.set_debug(DEBUG)
        nvim.loop.set_default_executor(self._pool)

        def cont() -> bool:
            rpc_atomic, specs = rpc.drain(nvim.channel_id)
            self._handlers.update(specs)

            try:
                self._stack = stack(self._pool, nvim=nvim)
            except (DecodeError, ValidationError) as e:
                tpl = """
                Some options may have changed.
                See help doc on Github under [docs/CONFIGURATION.md]


                ⚠️  ${e}
                """
                msg = Template(dedent(tpl)).substitute(e=e)
                write(nvim, msg, error=True)
                return False
            else:
                (rpc_atomic + autocmd.drain() + atomic).commit(nvim)
                set_options(
                    nvim,
                    mapping=self._stack.settings.keymap,
                    fast_close=self._stack.settings.display.pum.fast_close,
                )
                return True

        try:
            succ = threadsafe_call(nvim, cont)
        except Exception as e:
            log.exception("%s", e)
            return 1
        else:
            if not succ:
                return 1

        while True:
            msg: RpcMsg = self._event_queue.get()
            with with_suppress():
                threadsafe_call(nvim, self._handle, nvim, msg)
