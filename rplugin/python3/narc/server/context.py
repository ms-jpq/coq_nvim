from typing import Any, Dict, List, Set, Tuple

from pynvim import Nvim

from ..shared.consts import buf_var_name
from ..shared.nvim import call
from ..shared.parse import is_sym, is_word, normalize
from ..shared.types import Context, MatchOptions, Position
from .nvim import buf_get_var
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

    lit = reversed(line_before)
    l_alnums: List[str] = []
    l_syms: List[str] = []
    for c in lit:
        if is_word(c, unifying_chars=unifying_chars):
            l_alnums.append(c)
        else:
            if is_sym(c):
                l_syms.append(c)
            break

    for c in lit:
        if is_sym(c):
            l_syms.append(c)
        else:
            break

    rit = iter(line_after)
    r_alnums: List[str] = []
    r_syms: List[str] = []
    for c in rit:
        if is_word(c, unifying_chars=unifying_chars):
            r_alnums.append(c)
        else:
            if is_sym(c):
                r_syms.append(c)
            break

    for c in rit:
        if is_sym(c):
            r_syms.append(c)
        else:
            break

    alnums_before = "".join(reversed(l_alnums))
    alnums_before_normalized = normalize(alnums_before)

    alnums_after = "".join(r_alnums)
    alnums_after_normalized = normalize(alnums_after)

    alnums = alnums_before + alnums_after
    alnums_normalized = alnums_before_normalized + alnums_after_normalized

    syms_before = "".join(reversed(l_syms))
    syms_after = "".join(r_syms)
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


def gen_buf_ctx(buf_var: Dict[str, Any]) -> BufferContext:
    src = buf_var.get("sources") or {}
    sources = {key: BufferSourceSpec(**val) for key, val in src.items()}
    return BufferContext(sources=sources)


async def gen_context(
    nvim: Nvim, options: MatchOptions
) -> Tuple[Context, BufferContext]:
    def fed() -> Tuple[str, str, str, Position, Dict[str, Any]]:
        buffer = nvim.api.get_current_buf()
        filename = nvim.api.buf_get_name(buffer)
        filetype = nvim.api.buf_get_option(buffer, "filetype")
        window = nvim.api.get_current_win()
        row, col = nvim.api.win_get_cursor(window)
        line = nvim.api.get_current_line()
        buf_var = buf_get_var(nvim, buffer=buffer, name=buf_var_name) or {}
        row = row - 1
        position = Position(row=row, col=col)
        return filename, filetype, line, position, buf_var

    filename, filetype, line, position, buf_var = await call(nvim, fed)
    context = gen_ctx(
        filename=filename,
        filetype=filetype,
        line=line,
        position=position,
        unifying_chars=options.unifying_chars,
    )
    buffer_context = gen_buf_ctx(buf_var)
    return context, buffer_context


def goahead(context: Context) -> bool:
    return context.line_before != "" and not context.line_before.isspace()
