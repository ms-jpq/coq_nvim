from dataclasses import dataclass
from itertools import chain, repeat
from typing import Iterable, Iterator, MutableSequence, Sequence, Tuple

from pynvim import Nvim
from pynvim_pp.api import cur_win, win_get_buf, win_set_cursor
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
    primary: bool
    begin: NvimPos
    end: NvimPos
    cursor_offset: NvimPos
    replacement: Sequence[str]


@dataclass(frozen=True)
class _Lines:
    b_lines8: Sequence[bytes]
    b_lines16: Sequence[bytes]
    len8: Sequence[int]


def _lines(lines: Sequence[str]) -> _Lines:
    b_lines8 = tuple(line.encode(UTF8) for line in lines)
    return _Lines(
        b_lines8=b_lines8,
        b_lines16=tuple(line.encode(UTF16) for line in lines),
        len8=tuple(len(line) for line in b_lines8),
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


def _edit_trans(ctx: Context, env: EditEnv, edit: Edit) -> _EditInstruction:
    row, col = ctx.position

    c1 = len(ctx.line_before.encode(UTF8))
    c2 = c1 + len(ctx.words_before.encode(UTF8))

    begin = row, c1
    end = row, c2
    cursor_offset = 0, c1 - col
    replacement = tuple(line for line in edit.new_text.split(env.linefeed))

    inst = _EditInstruction(
        primary=True,
        begin=begin,
        end=end,
        cursor_offset=cursor_offset,
        replacement=replacement,
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
    replacement = tuple(line for line in edit.new_text.split(env.linefeed))

    inst = _EditInstruction(
        primary=True,
        begin=begin,
        end=end,
        cursor_offset=cursor_offset,
        replacement=replacement,
    )
    return inst


def _range_edit_trans(
    primary: bool, env: EditEnv, lines: _Lines, edit: RangeEdit
) -> _EditInstruction:
    (r1, ec1), (r2, ec2) = sorted((edit.begin, edit.end))

    assert edit.encoding == UTF16
    c1 = len(lines.b_lines16[ec1].decode(UTF16).encode(UTF8))
    c2 = len(lines.b_lines16[ec2].decode(UTF16).encode(UTF8))

    begin = r1, c1
    end = r2, c2
    cursor_offset = 0, 0
    replacement = tuple(line for line in edit.new_text.split(env.linefeed))

    inst = _EditInstruction(
        primary=primary,
        begin=begin,
        end=end,
        cursor_offset=cursor_offset,
        replacement=replacement,
    )
    return inst


def _consolidate(
    instruction: _EditInstruction, *instructions: _EditInstruction
) -> Sequence[_EditInstruction]:
    edits = sorted(chain((instruction,), instructions), key=lambda i: (i.begin, i.end))
    pivot = 0, 0
    stack: MutableSequence[_EditInstruction] = []

    for edit in edits:
        if edit.begin >= pivot:
            stack.append(edit)
            pivot = edit.end

        elif edit.primary:
            while stack:
                conflicting = stack.pop()
                if conflicting.end <= edit.begin:
                    break
            stack.append(edit)
            pivot = edit.end

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
            yield _edit_trans(ctx, env=env, edit=primary)

        elif isinstance(primary, ContextualEdit):
            yield _contextual_edit_trans(ctx, env=env, lines=lines, edit=primary)

        elif isinstance(primary, RangeEdit):
            yield _range_edit_trans(True, env=env, lines=lines, edit=primary)
        else:
            never(primary)

        for edit in secondary:
            yield _range_edit_trans(False, env=env, lines=lines, edit=edit)

    instructions = _consolidate(*cont())
    return instructions


def _commit(
    lines: _Lines, instructions: Iterable[_EditInstruction]
) -> Tuple[Sequence[str], NvimPos]:
    return (), (1, 1)


def edit(nvim: Nvim, ctx: Context, env: EditEnv, data: UserData) -> None:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
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
    new_lines, (n_row, n_col) = _commit(view, instructions=instructions)

    buf[lo:hi] = new_lines[lo:]
    win_set_cursor(nvim, win=win, row=n_row, col=n_col)

