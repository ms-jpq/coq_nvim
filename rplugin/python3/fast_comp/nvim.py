from asyncio import Future
from dataclasses import asdict, dataclass
from enum import Enum
from typing import Any, Awaitable, Callable, Dict, Iterable, Optional, Sequence, TypeVar
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


class VimCompKind(Enum):
    variable = "v"
    function = "f"
    member = "m"
    typedef = "t"
    define = "d"


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


def serialize(comp: VimCompletion) -> Dict[str, Any]:
    serialized = {k: v for k, v in asdict(comp).items() if v is not None}
    return serialized


async def complete(nvim: Nvim, col: int, comp: Sequence[VimCompletion]) -> None:
    serialized = tuple(map(serialize, comp))

    def cont() -> None:
        nvim.funcs.complete(col, serialized)

    await call(nvim, cont)
    await print(nvim, serialized)


async def col(nvim: Nvim) -> int:
    def cont() -> int:
        window = nvim.api.get_current_win()
        _, col = nvim.api.win_get_cursor(window)
        return col

    return await call(nvim, cont)
