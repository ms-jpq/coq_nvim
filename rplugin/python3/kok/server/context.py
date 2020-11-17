from typing import Any, Dict, Optional, Set, Tuple

from pynvim import Nvim

from ..shared.consts import buf_var_name
from ..shared.nvim import call
from ..shared.parse import normalize
from ..shared.types import Context, MatchOptions, Position
from .nvim import buf_get_var
from .parse import gen_lhs_rhs
from .types import BufferContext, BufferSourceSpec


def gen_ctx(
    filename: str,
    filetype: str,
    line: str,
    position: Position,
    unifying_chars: Set[str],
) -> Context:
    col = position.col
    line_before, line_after = line[:col], line[col:]

    syms_before, alnums_before, alnums_after, syms_after = gen_lhs_rhs(
        line_before, line_after, unifying_chars=unifying_chars
    )
    alnums = alnums_before + alnums_after

    alnums_before_normalized = normalize(alnums_before)
    alnums_after_normalized = normalize(alnums_after)
    alnums_normalized = alnums_before_normalized + alnums_after_normalized

    syms = syms_before + syms_after

    line_normalized = normalize(line)
    line_before_normalized = normalize(line_before)
    line_after_normalized = normalize(line_after)

    alnum_syms = syms_before + alnums + syms_after
    alnum_syms_normalized = syms_before + alnums_normalized + syms_after

    alnum_syms_before = syms_before + alnums_before
    alnum_syms_before_normalized = syms_before + alnums_before_normalized

    alnum_syms_after = alnums_after + syms_after
    alnum_syms_after_normalized = alnums_after_normalized + syms_after

    return Context(
        position=position,
        filename=filename,
        filetype=filetype,
        line=line,
        line_normalized=line_normalized,
        line_before=line_before,
        line_before_normalized=line_before_normalized,
        line_after=line_after,
        line_after_normalized=line_after_normalized,
        alnums=alnums,
        alnums_normalized=alnums_normalized,
        alnums_before=alnums_before,
        alnums_before_normalized=alnums_before_normalized,
        alnums_after=alnums_after,
        alnums_after_normalized=alnums_after_normalized,
        syms=syms,
        syms_before=syms_before,
        syms_after=syms_after,
        alnum_syms=alnum_syms,
        alnum_syms_normalized=alnum_syms_normalized,
        alnum_syms_before=alnum_syms_before,
        alnum_syms_before_normalized=alnum_syms_before_normalized,
        alnum_syms_after=alnum_syms_after,
        alnum_syms_after_normalized=alnum_syms_after_normalized,
    )


async def gen_buf_ctx(nvim: Nvim) -> BufferContext:
    def cont() -> BufferContext:
        buffer = nvim.api.get_current_buf()
        buf_var: Dict[str, Any] = (
            buf_get_var(nvim, buffer=buffer, name=buf_var_name) or {}
        )
        src = buf_var.get("sources") or {}
        sources = {key: BufferSourceSpec(**val) for key, val in src.items()}
        return BufferContext(sources=sources)

    return await call(nvim, cont)


async def gen_context(
    nvim: Nvim, options: MatchOptions, pos: Optional[Position]
) -> Context:
    def cont() -> Tuple[str, str, str, Position]:
        buffer = nvim.api.get_current_buf()
        filename = nvim.api.buf_get_name(buffer)
        filetype = nvim.api.buf_get_option(buffer, "filetype")
        window = nvim.api.get_current_win()
        row, col = (pos.row, pos.col) if pos else nvim.api.win_get_cursor(window)
        row = row if pos else row - 1
        line = nvim.api.get_current_line()
        position = Position(row=row, col=col)
        return filename, filetype, line, position

    filename, filetype, line, position = await call(nvim, cont)
    context = gen_ctx(
        filename=filename,
        filetype=filetype,
        line=line,
        position=position,
        unifying_chars=options.unifying_chars,
    )
    return context


def goahead(context: Context) -> bool:
    return context.line_before != "" and not context.line_before.isspace()
