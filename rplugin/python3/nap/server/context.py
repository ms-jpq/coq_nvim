from typing import List, Set, Tuple

from pynvim import Nvim

from ..shared.nvim import call
from ..shared.parse import is_sym, is_word, normalize
from ..shared.types import Context, MatchOptions, Position


def gen_ctx(
    filename: str,
    filetype: str,
    line: str,
    position: Position,
    unifying_chars: Set[str],
) -> Context:
    col = position.col
    line_before = line[:col]
    line_after = line[col:]

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

    syms_before = "".join(reversed(l_syms))
    syms_after = "".join(r_syms)
    syms = syms_before + syms_after

    line_normalized = normalize(line)
    line_before_normalized = normalize(line_before)
    line_after_normalized = normalize(line_after)
    alnums_normalized = normalize(alnums)

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
        alnums_before=alnums_before,
        alnums_before_normalized=alnums_before_normalized,
        alnums_after=alnums_after,
        alnums_after_normalized=alnums_after_normalized,
        syms=syms,
        syms_before=syms_before,
        syms_after=syms_after,
        alnums_normalized=alnums_normalized,
    )


async def gen_context(nvim: Nvim, options: MatchOptions) -> Context:
    def fed() -> Tuple[str, str, str, Position]:
        buffer = nvim.api.get_current_buf()
        filename = nvim.api.buf_get_name(buffer)
        filetype = nvim.api.buf_get_option(buffer, "filetype")
        window = nvim.api.get_current_win()
        row, col = nvim.api.win_get_cursor(window)
        line = nvim.api.get_current_line()
        row = row - 1
        position = Position(row=row, col=col)
        return filename, filetype, line, position

    filename, filetype, line, position = await call(nvim, fed)
    context = gen_ctx(
        filename=filename,
        filetype=filetype,
        line=line,
        position=position,
        unifying_chars=options.unifying_chars,
    )
    return context
