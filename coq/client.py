from asyncio.events import AbstractEventLoop
from concurrent.futures import ThreadPoolExecutor
from logging import DEBUG as DEBUG_LV
from logging import INFO
from multiprocessing import cpu_count
from queue import SimpleQueue
from string import Template
from sys import stderr
from textwrap import dedent
from typing import Any, MutableMapping, Optional, cast

from pynvim import Nvim
from pynvim_pp.client import Client
from pynvim_pp.lib import threadsafe_call, write
from pynvim_pp.logging import log, with_suppress
from pynvim_pp.rpc import RpcCallable, RpcMsg, nil_handler
from std2.functools import constantly
from std2.pickle import DecodeError
from std2.types import AnyFun

from ._registry import ____
from .consts import DEBUG, DEBUG_DB, DEBUG_METRICS, TMP_DIR
from .registry import atomic, autocmd, rpc
from .server.registrants.attachment import BUF_EVENTS
from .server.registrants.options import set_options
from .server.rt_types import Stack
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
    def __init__(self) -> None:
        self._pool = ThreadPoolExecutor(max_workers=min(16, cpu_count() + 8))
        self._handlers: MutableMapping[str, RpcCallable] = {}
        self._event_queue: SimpleQueue = SimpleQueue()
        self._stack: Optional[Stack] = None

    def _handle(self, nvim: Nvim, msg: RpcMsg) -> Any:
        name, args = msg
        if name.startswith("nvim_buf_"):
            handler = cast(AnyFun[None], BUF_EVENTS.get(name, _FN))
            return handler(nvim, self._stack, *args)
        else:
            handler = cast(AnyFun[None], self._handlers.get(name, nil_handler(name)))
            a, *_ = args
            return handler(nvim, self._stack, *a)

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

        def cont() -> None:
            rpc_atomic, specs = rpc.drain(nvim.channel_id)
            self._handlers.update(specs)

            self._stack = stack(self._pool, nvim=nvim)
            (rpc_atomic + autocmd.drain() + atomic).commit(nvim)
            set_options(nvim, mapping=self._stack.settings.keymap)

        try:
            threadsafe_call(nvim, cont)
        except DecodeError as e:
            tpl = """
            Some options may hanve changed.
            See help doc on Github under [docs/CONFIGURATION.md]


            ${e}
            """
            ms = Template(dedent(tpl)).substitute(e=e)
            print(ms, file=stderr, flush=True)
            return 1
        except Exception as e:
            log.exception("%s", e)
            return 1

        while True:
            msg: RpcMsg = self._event_queue.get()
            with with_suppress():
                threadsafe_call(nvim, self._handle, nvim, msg)
