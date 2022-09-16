from asyncio import get_event_loop
from concurrent.futures import ThreadPoolExecutor
from functools import wraps
from logging import DEBUG as DEBUG_LV
from logging import INFO
from pathlib import PurePath
from string import Template
from sys import exit
from textwrap import dedent
from typing import Any, Optional, Sequence, cast

from pynvim_pp.logging import log, suppress_and_log
from pynvim_pp.nvim import Nvim, conn
from pynvim_pp.rpc import MsgType
from pynvim_pp.types import Method, NoneType, RPCallable
from std2.cell import RefCell
from std2.pickle.types import DecodeError

from ._registry import ____
from .consts import DEBUG, DEBUG_DB, DEBUG_METRICS, TMP_DIR
from .registry import atomic, autocmd, rpc
from .server.registrants.options import set_options
from .server.rt_types import Stack, ValidationError
from .server.runtime import stack

assert ____ or True

_CB = RPCallable[None]
_CELL = RefCell[Optional[Stack]](None)


def _set_debug() -> None:
    if DEBUG or DEBUG_METRICS or DEBUG_DB:
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        log.setLevel(DEBUG_LV)
    else:
        log.setLevel(INFO)


async def _default(msg: MsgType, method: Method, params: Sequence[Any]) -> None:
    with suppress_and_log():
        assert False, (msg, method, params)


def _trans(handler: _CB) -> _CB:
    @wraps(handler)
    async def f(*params: Any) -> None:
        stack = _CELL.val
        return await f(stack, *params)

    return cast(_CB, f)


async def init(socket: PurePath) -> None:
    with ThreadPoolExecutor(max_workers=69) as pool:
        async with conn(socket, default=_default) as client:
            loop = get_event_loop()
            loop.set_default_executor(pool)
            _set_debug()
            rpc_atomic, handlers = rpc.drain()
            for handler in handlers.values():
                hldr = _trans(handler)
                client.register(hldr)

            await (rpc_atomic + autocmd.drain() + atomic).commit(NoneType)
            try:
                _CELL.val = stk = await stack(pool)
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
                await set_options(
                    mapping=stk.settings.keymap,
                    fast_close=stk.settings.display.pum.fast_close,
                )
