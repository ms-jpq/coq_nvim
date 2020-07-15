from asyncio import Future
from typing import Any, Awaitable, Callable, Dict, Iterable, Sequence, TypeVar
from uuid import uuid4

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


async def autocmd(
    nvim: Nvim,
    *,
    events: Iterable[str],
    fn: str,
    filters: Iterable[str] = ("*",),
    modifiers: Iterable[str] = (),
    arg_eval: Iterable[str] = (),
) -> None:
    _events = ",".join(events)
    _filters = " ".join(filters)
    _modifiers = " ".join(modifiers)
    _args = ", ".join(arg_eval)
    group = f"augroup {uuid4()}"
    cls = "autocmd!"
    cmd = f"autocmd {_events} {_filters} {_modifiers} call {fn}({_args})"
    group_end = "augroup END"

    def cont() -> None:
        nvim.api.command(group)
        nvim.api.command(cls)
        nvim.api.command(cmd)
        nvim.api.command(group_end)

    await call(nvim, cont)


def buffer_keymap(nvim: Nvim, buffer: Buffer, keymap: Dict[str, Sequence[str]]) -> None:
    options = {"noremap": True, "silent": True, "nowait": True}

    for function, mappings in keymap.items():
        for mapping in mappings:
            nvim.api.buf_set_keymap(
                buffer, "n", mapping, f"<cmd>call {function}(v:false)<cr>", options
            )
            nvim.api.buf_set_keymap(
                buffer, "v", mapping, f"<esc><cmd>call {function}(v:true)<cr>", options,
            )
