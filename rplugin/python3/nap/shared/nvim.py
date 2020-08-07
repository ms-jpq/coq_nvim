from asyncio import Future
from os import linesep
from typing import Any, Awaitable, Callable, Sequence, Tuple, TypeVar

from pynvim import Nvim
from pynvim.api.common import NvimError


T = TypeVar("T")


def atomic(nvim: Nvim, *instructions: Tuple[str, Sequence[str]]) -> Sequence[Any]:
    inst = tuple((f"nvim_{instruction}", args) for instruction, args in instructions)
    out, err = nvim.api.call_atomic(inst)
    if err:
        raise NvimError(err)
    return out


def call(nvim: Nvim, fn: Callable[[], T]) -> Awaitable[T]:
    fut: Future = Future()

    def cont() -> None:
        try:
            ret = fn()
        except Exception as e:
            fut.set_exception(e)
        else:
            if not fut.cancelled():
                fut.set_result(ret)

    nvim.async_call(cont)
    return fut


async def print(
    nvim: Nvim, message: Any, error: bool = False, flush: bool = True
) -> None:
    write = nvim.api.err_write if error else nvim.api.out_write

    def cont() -> None:
        msg = str(message) + (linesep if flush else "")
        write(msg)

    await call(nvim, cont)
