from dataclasses import dataclass
from functools import cache
from itertools import chain, repeat
from typing import Iterable, Iterator, MutableSequence, Sequence, Tuple

from pynvim import Nvim
from pynvim_pp.api import cur_buf
from std2.types import never

from ..shared.types import (
    UTF8,
    UTF16,
    ApplicableEdit,
    Context,
    ContextualEdit,
    Edit,
    EditEnv,
    NvimPos,
    RangeEdit,
    SnippetEdit,
)
from ..snippets.parse import parse
from .context import edit_env
from .types import UserData


@dataclass(frozen=True)
class _EditInstruction:
    begin: NvimPos
    end: NvimPos
    cursor_offset: NvimPos
    replacement: bytes


@dataclass(frozen=True)
class _Lines:
    len8: Sequence[int]
    len16: Sequence[int]


def _lines(lines: Sequence[str]) -> _Lines:
    return _Lines(
        len8=tuple(len(line.encode(UTF8)) for line in lines),
        len16=tuple(len(line.encode(UTF16)) // 2 for line in lines),
    )


def _rows_to_fetch(
    pos: NvimPos, env: EditEnv, edit: ApplicableEdit, *edits: ApplicableEdit
) -> Tuple[int, int]:
    row, _ = pos

    def cont() -> Iterator[int]:
        for e in chain((edit,), edits):
            if isinstance(e, Edit):
                yield row

            elif isinstance(e, RangeEdit):
                (lo, _), (hi, _) = e.begin, e.end
                yield from (lo, hi)

            elif isinstance(e, ContextualEdit):
                lo = row - len(e.old_prefix.split(env.linefeed)) - 1
                hi = row + len(e.old_suffix.split(env.linefeed)) - 1
                yield from (lo, hi)

            else:
                never(e)

    line_nums = tuple(cont())
    return min(line_nums), max(line_nums) + 1


def _edit_trans(ctx: Context, edit: Edit) -> _EditInstruction:
    row, col = ctx.position

    c1 = len(ctx.line_before.encode(UTF8))
    c2 = c1 + len(ctx.words_before.encode(UTF8))

    begin = row, c1
    end = row, c2
    cursor_offset = 0, c1 - col

    inst = _EditInstruction(
        begin=begin,
        end=end,
        cursor_offset=cursor_offset,
        replacement=edit.new_text.encode(UTF8),
    )
    return inst


def _contextual_edit_trans(
    ctx: Context, env: EditEnv, lines: _Lines, edit: ContextualEdit
) -> _EditInstruction:
    row, col = ctx.position
    prefix_lines = edit.old_prefix.split(env.linefeed)
    suffix_lines = edit.old_suffix.split(env.linefeed)

    r1 = row - len(prefix_lines) - 1
    r2 = row + len(suffix_lines) - 1

    c1 = (
        lines.len8[r1] - len(prefix_lines[0].encode(UTF8))
        if len(prefix_lines) > 1
        else col - len(prefix_lines[0].encode(UTF8))
    )
    c2 = (
        len(suffix_lines[-1].encode(UTF8))
        if len(prefix_lines) > 1
        else col + len(suffix_lines[0].encode(UTF8))
    )

    begin = r1, c1
    end = r2, c2
    cursor_offset = 0, 0

    inst = _EditInstruction(
        begin=begin,
        end=end,
        cursor_offset=cursor_offset,
        replacement=edit.new_text.encode(UTF8),
    )
    return inst


def _range_edit_trans(ctx: Context, lines: _Lines, edit: RangeEdit) -> _EditInstruction:
    (r1, ec1), (r2, ec2) = edit.begin, edit.end

    c1 = len(ctx.line_before.encode(UTF8))
    c2 = c1 + len(ctx.words_before.encode(UTF8))

    begin = r1, c1
    end = r2, c2

    inst = _EditInstruction(
        begin=begin,
        end=end,
        cursor_offset=(0, 0),
        replacement=edit.new_text.encode(UTF8),
    )
    return inst


def _consolidate(
    instruction: _EditInstruction, *instructions: _EditInstruction
) -> Sequence[_EditInstruction]:
    edits = sorted(chain((instruction,), instructions), key=lambda i: (i.begin, i.end))
    pivot = 0
    stack: MutableSequence[_EditInstruction] = []
    for edit in edits:
        if edit.begin >= pivot:
            stack.append(edit)
        elif edit.is_cursor:
            if stack:
                stack.pop()
            stack.append(edit)
        else:
            pass
    return stack


def _instructions(
    ctx: Context,
    env: EditEnv,
    lines: _Lines,
    primary: ApplicableEdit,
    secondary: Sequence[RangeEdit],
) -> Sequence[_EditInstruction]:
    def cont() -> Iterator[_EditInstruction]:
        if isinstance(primary, Edit):
            yield _edit_trans(ctx, edit=primary)

        elif isinstance(primary, ContextualEdit):
            yield _contextual_edit_trans(ctx, env=env, lines=lines, edit=primary)

        elif isinstance(primary, RangeEdit):
            yield _range_edit_trans(ctx, lines=lines, edit=primary)
        else:
            never(primary)

        for edit in secondary:
            yield _range_edit_trans(ctx, lines=lines, edit=edit)

    instructions = _consolidate(*cont())
    return instructions


def _commit(nvim: Nvim, instructions: Iterable[_EditInstruction]) -> None:
    pass


def edit(nvim: Nvim, ctx: Context, env: EditEnv, data: UserData) -> None:
    buf = cur_buf(nvim)
    env = edit_env(nvim, buf=buf)

    primary = (
        parse(nvim, env=env, snippet=data.primary_edit)
        if isinstance(data.primary_edit, SnippetEdit)
        else data.primary_edit
    )
    lo, hi = _rows_to_fetch(ctx.position, env, primary, *data.secondary_edits)
    lines = tuple(chain(repeat("", times=lo), buf[lo:hi]))
    view = _lines(lines)

    instructions = _instructions(
        ctx, env=env, lines=view, primary=primary, secondary=data.secondary_edits
    )
    _commit(nvim, instructions=instructions)

