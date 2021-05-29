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

from .registry import atomic, autocmd, rpc
from .shared.settings import Settings
from .types import State


class CoqClient(Client):
    def __init__(self) -> None:
        self._handlers: MutableMapping[str, RpcCallable] = {}
        self._pool, self._events = ThreadPoolExecutor(), SimpleQueue()

        self._state = State()
        self._settings: Optional[Settings] = None

    def on_msg(self, nvim: Nvim, msg: RpcMsg) -> Any:
        self._events.put(msg)
        return None

    def wait(self, nvim: Nvim) -> int:
        def cont() -> None:
            if isinstance(nvim.loop, AbstractEventLoop):
                nvim.loop.set_default_executor(self._pool)

            rpc_atomic, specs = rpc.drain(nvim.channel_id)
            self._handlers.update(specs)
            (rpc_atomic + autocmd.drain()).commit(nvim)

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
            handler = cast(AnyFun[None], self._handlers.get(name, nil_handler(name)))

            try:
                handler(nvim, *args)
            except Exception as e:
                log.exception("%s", e)
