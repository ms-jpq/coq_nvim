from concurrent.futures import ThreadPoolExecutor
from multiprocessing import cpu_count
from queue import SimpleQueue
from typing import Any, Callable

from pynvim_pp.atomic import Atomic
from pynvim_pp.autocmd import AutoCMD
from pynvim_pp.logging import log
from pynvim_pp.rpc import RPC, RpcCallable, RpcMsg


def _name_gen(fn: Callable[[Callable[..., Any]], str]) -> str:
    return f"COQ{fn.__qualname__.lstrip('_')}"


pool = ThreadPoolExecutor(max_workers=min(32, cpu_count() + 10))
event_queue: SimpleQueue = SimpleQueue()

autocmd = AutoCMD()
atomic = Atomic()
rpc = RPC(name_gen=_name_gen)


def enqueue_event(event: RpcCallable, *args: Any) -> None:
    try:
        msg: RpcMsg = (event.name, (args,))
        event_queue.put(msg)
    except Exception as e:
        log.exception("%s", e)
        raise

