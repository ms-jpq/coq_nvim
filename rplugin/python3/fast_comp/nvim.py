from asyncio import Future
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, Optional, Sequence, TypeVar

from pynvim import Nvim

Tabpage = Any
Window = Any
Buffer = Any

T = TypeVar("T")


def call(nvim: Nvim, fn: Callable[[], T]) -> Awaitable[T]:
    fut: Future = Future()

    def cont() -> None:
        try:
            ret = fn()
        except Exception as e:
            fut.set_exception(e)
        else:
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
            write("\n")

    await call(nvim, cont)


@dataclass(frozen=True)
class VimCompletion:
    word: str
    abbr: Optional[str] = None
    menu: Optional[str] = None
    info: Optional[str] = None
    kind: Optional[str] = None
    icase: Optional[int] = None
    equal: Optional[int] = None
    dup: Optional[int] = None
    empty: Optional[int] = None
    user_data: Optional[Any] = None


def complete(nvim: Nvim, comp: Sequence[VimCompletion]) -> Callable[[], None]:
    def cont() -> None:
        window = nvim.api.get_current_win()
        _, col = nvim.api.win_get_cursor(window)
        nvim.funcs.complete(col, comp)

    return cont
