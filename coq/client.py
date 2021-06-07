from asyncio.events import AbstractEventLoop
from concurrent.futures import ThreadPoolExecutor
from os import linesep
from queue import SimpleQueue
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
from .registry import atomic, autocmd, rpc
from .server.registrants.attachment import BUF_EVENTS
from .server.runtime import Stack, stack


class CoqClient(Client):
    def __init__(self) -> None:
        self._handlers: MutableMapping[str, RpcCallable] = {}
        self._pool, self._events = ThreadPoolExecutor(), SimpleQueue()

        self._stack: Optional[Stack] = None

    def on_msg(self, nvim: Nvim, msg: RpcMsg) -> Any:
        self._events.put(msg)
        return None

    def wait(self, nvim: Nvim) -> int:
        def cont() -> None:
            if isinstance(nvim.loop, AbstractEventLoop):
                nvim.loop.set_default_executor(self._pool)

            rpc_atomic, specs = rpc.drain(nvim.channel_id)
            self._handlers.update(specs)
            (rpc_atomic + autocmd.drain() + atomic).commit(nvim)

            self._stack = stack(self._pool,nvim=nvim)

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
            msg: RpcMsg = self._events.get()
            name, args = msg

            def handle() -> None:
                if name.startswith("nvim_buf_"):
                    handler = BUF_EVENTS[name]
                    handler(nvim, self._stack, *args)
                else:
                    handler = cast(
                        AnyFun[None], self._handlers.get(name, nil_handler(name))
                    )
                    a, *_ = args
                    handler(nvim, self._stack, *a)

            try:
                threadsafe_call(nvim, handle)
            except Exception as e:
                log.exception("%s", e)
