from asyncio.events import AbstractEventLoop
from logging import DEBUG as DEBUG_LV
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
from .consts import DEBUG
from .registry import atomic, autocmd, event_queue, pool, rpc
from .server.options import set_options
from .server.registrants.attachment import BUF_EVENTS
from .server.runtime import Stack, stack

if DEBUG:
    log.setLevel(DEBUG_LV)


class CoqClient(Client):
    def __init__(self) -> None:
        self._handlers: MutableMapping[str, RpcCallable] = {}
        self._stack: Optional[Stack] = None

    def _handle(self, nvim: Nvim, msg: RpcMsg) -> Any:
        name, args = msg

        if name.startswith("nvim_buf_"):
            handler = cast(AnyFun[None], BUF_EVENTS[name])
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
        if isinstance(nvim.loop, AbstractEventLoop):
            nvim.loop.set_default_executor(pool)

        def cont() -> None:
            rpc_atomic, specs = rpc.drain(nvim.channel_id)
            self._handlers.update(specs)

            self._stack = stack(pool, nvim=nvim)
            (rpc_atomic + autocmd.drain() + atomic).commit(nvim)
            set_options(nvim, mapping=self._stack.settings.keymap)

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

