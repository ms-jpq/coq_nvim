from asyncio import get_running_loop
from asyncio.exceptions import CancelledError
from contextlib import suppress
from functools import wraps
from logging import DEBUG as DEBUG_LV
from logging import INFO
from pathlib import PurePath
from string import Template
from sys import exit
from textwrap import dedent
from typing import Any, Sequence, cast

from pynvim_pp.logging import log, suppress_and_log
from pynvim_pp.nvim import Nvim, conn
from pynvim_pp.rpc import MsgType
from pynvim_pp.types import Method, NoneType, RPCallable
from std2.pickle.types import DecodeError

from ._registry import ____
from .consts import DEBUG, DEBUG_DB, DEBUG_METRICS, TMP_DIR
from .registry import atomic, autocmd, rpc
from .server.registrants.options import set_options
from .server.rt_types import Stack, ValidationError
from .server.runtime import stack

assert ____ or True

_CB = RPCallable[None]
_IGNORE = {"nvim_buf_changedtick_event", "nvim_buf_detach_event"}


def _set_debug() -> None:
    loop = get_running_loop()
    loop.set_debug(DEBUG)
    if DEBUG or DEBUG_METRICS or DEBUG_DB:
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        log.setLevel(DEBUG_LV)
    else:
        log.setLevel(INFO)


async def _default(msg: MsgType, method: Method, params: Sequence[Any]) -> None:
    if method not in _IGNORE:
        with suppress_and_log():
            assert False, (msg, method, params)


def _trans(stack: Stack, handler: _CB) -> _CB:
    @wraps(handler)
    async def f(*params: Any) -> None:
        with suppress(CancelledError):
            return await handler(stack, *params)

    return cast(_CB, f)


async def init(socket: PurePath) -> None:
    _set_debug()

    async with conn(socket, default=_default) as client:
        try:
            stk = await stack()
        except (DecodeError, ValidationError) as e:
            tpl = """
                Some options may have changed.
                See help doc on Github under [docs/CONFIGURATION.md]


                ⚠️  ${e}
                """
            msg = Template(dedent(tpl)).substitute(e=e)
            await Nvim.write(msg, error=True)
            exit(1)
        else:
            rpc_atomic, handlers = rpc.drain()
            for handler in handlers.values():
                hldr = _trans(stk, handler=handler)
                client.register(hldr)

            await (rpc_atomic + autocmd.drain() + atomic).commit(NoneType)
            await set_options(
                mapping=stk.settings.keymap,
                fast_close=stk.settings.display.pum.fast_close,
            )
