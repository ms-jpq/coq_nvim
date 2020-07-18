from asyncio import Future
from dataclasses import asdict, dataclass
from enum import Enum
from typing import (
    Any,
    Awaitable,
    Callable,
    Dict,
    Iterable,
    Iterator,
    Optional,
    Tuple,
    TypeVar,
)
from uuid import uuid4

from pynvim import Nvim
from pynvim.api.common import NvimError

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


async def complete(nvim: Nvim, col: int, comp: Iterator[VimCompletion]) -> None:
    serialized = tuple(map(serialize, comp))

    def cont() -> None:
        try:
            nvim.funcs.complete(col + 1, serialized)
        except NvimError:
            pass

    await call(nvim, cont)


def cur_pos(nvim: Nvim) -> Tuple[int, int]:
    window = nvim.api.get_current_win()
    row, col = nvim.api.win_get_cursor(window)
    return row, col
