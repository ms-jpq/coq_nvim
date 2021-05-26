from asyncio.events import AbstractEventLoop
from concurrent.futures import ThreadPoolExecutor
from os import linesep
from queue import SimpleQueue
from sys import stderr
from time import monotonic
from typing import Any, MutableMapping, Optional, cast

from pynvim import Nvim
from pynvim.api.common import NvimError
from pynvim_pp.client import Client
from pynvim_pp.highlight import highlight
from pynvim_pp.lib import threadsafe_call, write
from pynvim_pp.logging import log
from pynvim_pp.rpc import RpcCallable, RpcMsg, nil_handler
from std2.pickle import DecodeError
from std2.types import AnyFun

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

            atomic, specs = rpc.drain(nvim.channel_id)
            self._handlers.update(specs)
            self._settings = initial_settings(nvim, specs)
            hl = highlight(*self._settings.view.hl_context.groups)
            (atomic + autocmd.drain() + hl).commit(nvim)

            self._state = initial_state(nvim, settings=self._settings)
            init_locale(self._settings.lang)

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
        else:
            settings = cast(Settings, self._settings)


        while True:
            msg: RpcMsg = event_queue.get()
            name, args = msg
            handler = cast(
                AnyFun[Optional[Stage]], self._handlers.get(name, nil_handler(name))
            )

            def cdraw() -> None:
                nonlocal has_drawn
                stage = handler(nvim, self._state, settings, *args)
                if stage:
                    self._state = stage.state

                    for _ in range(RENDER_RETRIES - 1):
                        try:
                            redraw(nvim, state=self._state, focus=stage.focus)
                        except NvimError as e:
                            write(nvim, f"recoverable error - {e}")
                        else:
                            break
                    else:
                        redraw(nvim, state=self._state, focus=stage.focus)


            try:
                threadsafe_call(nvim, cdraw)
            except Exception as e:
                log.exception("%s", e)
