from asyncio.events import AbstractEventLoop
from concurrent.futures import ThreadPoolExecutor
from os import linesep
from sys import stderr
from typing import Any, MutableMapping, Optional, cast

from pynvim import Nvim
from pynvim_pp.client import Client
from pynvim_pp.lib import threadsafe_call
from pynvim_pp.logging import log
from pynvim_pp.rpc import RpcCallable, RpcMsg, nil_handler
from std2.pickle import DecodeError
from std2.types import AnyFun

from ._registry import ____
from .registry import atomic, autocmd, event_queue, rpc, settings
from .server.registrants.attachment import BUF_EVENTS
from .server.runtime import Stack, stack


class CoqClient(Client):
    def __init__(self) -> None:
        self._handlers: MutableMapping[str, RpcCallable] = {}
        self._pool = ThreadPoolExecutor()

        self._stack: Optional[Stack] = None

    def _handle(self, nvim: Nvim, msg: RpcMsg) -> Any:
        name, args = msg

        if name.startswith("nvim_buf_"):
            handler = BUF_EVENTS[name]
            return handler(nvim, self._stack, *args)
        else:
            handler = cast(AnyFun[None], self._handlers.get(name, nil_handler(name)))
            a, *_ = args
            return handler(nvim, self._stack, *a)

    def on_msg(self, nvim: Nvim, msg: RpcMsg) -> Any:
        if not self._stack:
            event_queue.put(msg)
            return None
        else:
            return self._handle(nvim, msg)

    def wait(self, nvim: Nvim) -> int:
        def cont() -> None:
            if isinstance(nvim.loop, AbstractEventLoop):
                nvim.loop.set_default_executor(self._pool)

            rpc_atomic, specs = rpc.drain(nvim.channel_id)
            self._handlers.update(specs)
            (rpc_atomic + autocmd.drain() + atomic + settings.drain()).commit(nvim)

            self._stack = stack(self._pool, nvim=nvim)

        try:
            threadsafe_call(nvim, cont)
        except DecodeError as e:
            msg1 = "Some options may hanve changed."
            msg2 = "See help doc on Github under [docs/CONFIGURATION.md]"
            print(e, msg1, msg2, sep=linesep, file=stderr)
            return 1
        except Exception as e:
            log.exception("%s", e)
            return 1

        while True:
            msg: RpcMsg = event_queue.get()
            try:
                threadsafe_call(nvim, self._handle, nvim, msg)
            except Exception as e:
                log.exception("%s", e)
