from typing import Any, Callable

from pynvim_pp.atomic import Atomic
from pynvim_pp.autocmd import AutoCMD
from pynvim_pp.rpc import RPC

NAMESPACE = "COQ"


def _name_gen(fn: Callable[[Callable[..., Any]], str]) -> str:
    return fn.__qualname__.lstrip("_").capitalize()


autocmd = AutoCMD()
atomic = Atomic()
rpc = RPC(NAMESPACE, name_gen=_name_gen)
