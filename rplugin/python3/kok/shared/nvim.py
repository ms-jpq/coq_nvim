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

async def autocmd(
    nvim: Nvim,
    *,
    name: str,
    events: Iterable[str],
    filters: Iterable[str] = ("*",),
    modifiers: Iterable[str] = (),
    arg_eval: Iterable[str] = (),
) -> None:
    _events = ",".join(events)
    _filters = " ".join(filters)
    _modifiers = " ".join(modifiers)
    _args = ", ".join(arg_eval)
    group = f"augroup {uuid4().hex}"
    cls = "autocmd!"
    cmd = (
        f"autocmd {_events} {_filters} {_modifiers} call _KoKnotify('{name}', {_args})"
    )
    group_end = "augroup END"

    def cont() -> None:
        commands = linesep.join((group, cls, cmd, group_end))
        nvim.api.exec(commands, False)

    await call(nvim, cont)


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