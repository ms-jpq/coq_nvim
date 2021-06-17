from typing import Iterator, Sequence, Tuple

from pynvim import Nvim
from pynvim.api import Buffer, Window

from ..shared.da import expand_tabs
from ..shared.logging import log
from ..shared.nvim import call
from ..shared.types import Context, Position
from .edit import edit
from .parser import Parsed
from .settings import instance
from .types import Expanded, InstanceSettings


def indent_by(context: Context, settings: InstanceSettings) -> str:
    before_len = len(context.line[: context.position.col])
    tabsize = settings.tab_width
    if settings.prefer_tabs:
        return "\t" * (before_len // tabsize) + " " * (before_len % tabsize)
    else:
        return " " * before_len


def expand_parsed(
    context: Context, settings: InstanceSettings, parsed: Parsed
) -> Expanded:
    before, after = (
        context.line[: context.position.col],
        context.line[context.position.col :],
    )
    indent = indent_by(context, settings=settings)
    pre = before[: len(context.alnum_syms_before) * -1]
    it = iter(parsed.text.splitlines(True))

    def cont() -> Iterator[str]:
        l1 = next(it, "")
        yield pre
        yield l1
        for line in it:
            yield indent
            yield line
        yield after

    raw = "".join(cont())

    if settings.prefer_tabs:
        return Expanded(text=raw, pos=Position(row=0, col=0), marks=())
    else:
        text = expand_tabs(raw, tab_width=settings.tab_width)
        return Expanded(text=text, pos=Position(row=0, col=0), marks=())


async def apply(nvim: Nvim, context: Context, parsed: Parsed) -> None:
    settings = await instance(nvim)
    expanded = expand_parsed(context, settings=settings, parsed=parsed)

    def cont() -> None:
        edit(nvim, context=context, expanded=expanded)

    await call(nvim, cont)
