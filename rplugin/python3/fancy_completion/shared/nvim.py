from asyncio import Future, Task, create_task, sleep
from os import linesep
from traceback import format_exc
from typing import Any, Awaitable, Callable, TypeVar

from pynvim import Nvim

T = TypeVar("T")


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
        write(str(message))
        if flush:
            write(linesep)

    await call(nvim, cont)


def run_forever(
    nvim: Nvim,
    thing: Callable[[], Awaitable[None]],
    retries: int = 3,
    timeout: float = 1.0,
) -> Task:
    async def loop() -> None:
        for _ in range(retries):
            try:
                await thing()
            except Exception as e:
                stack = format_exc()
                await print(nvim, f"{stack}{e}", error=True)
                await sleep(timeout)

    return create_task(loop())
