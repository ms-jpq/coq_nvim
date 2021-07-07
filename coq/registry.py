from typing import Any, Callable

from pynvim_pp.atomic import Atomic
from pynvim_pp.autocmd import AutoCMD
from pynvim_pp.rpc import RPC


def _name_gen(fn: Callable[[Callable[..., Any]], str]) -> str:
    return f"COQ{fn.__qualname__.lstrip('_')}"


autocmd = AutoCMD()
atomic = Atomic()
rpc = RPC(name_gen=_name_gen)

