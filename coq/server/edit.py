from dataclasses import dataclass
from itertools import chain, repeat
from pprint import pformat
from string import Template
from textwrap import dedent
from typing import (
    AbstractSet,
    Iterable,
    Iterator,
    MutableMapping,
    MutableSequence,
    Optional,
    Sequence,
    Tuple,
)
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer, Window
from pynvim.api.common import NvimError
from pynvim_pp.api import (
    buf_commentstr,
    buf_get_extmarks,
    buf_get_lines,
    buf_set_text,
    create_ns,
    cur_win,
    win_get_buf,
    win_get_cursor,
    win_set_cursor,
)
from pynvim_pp.lib import decode, encode, write
from pynvim_pp.logging import log
from std2.types import never

from ..consts import DEBUG
from ..lang import LANG
from ..shared.runtime import Metric
from ..shared.trans import trans_adjusted
from ..shared.types import (
    UTF8,
    UTF16,
    Completion,
    Context,
    ContextualEdit,
    Edit,
    Mark,
    NvimPos,
    RangeEdit,
    SnippetEdit,
    SnippetRangeEdit,
)
from ..snippets.parse import ParsedEdit, parse_norm, parse_range
from ..snippets.parsers.types import ParseError, ParseInfo
from .mark import mark
from .rt_types import Stack
from .state import State

NS = uuid4()


@dataclass(frozen=True)
class EditInstruction:
    primary: bool
    begin: NvimPos
    end: NvimPos
    cursor_yoffset: int
    cursor_xpos: int
    new_lines: Sequence[str]


@dataclass(frozen=True)
class _Lines:
    lines: Sequence[str]
    b_lines8: Sequence[bytes]
    b_lines16: Sequence[bytes]
    len8: Sequence[int]


def _lines(lines: Sequence[str]) -> _Lines:
    b_lines8 = tuple(map(encode, lines))
    return _Lines(
        lines=lines,
        b_lines8=b_lines8,
        b_lines16=tuple(encode(line, encoding=UTF16) for line in lines),
        len8=tuple(len(line) for line in b_lines8),
    )


def _rows_to_fetch(ctx: Context, edit: Edit, *edits: Edit) -> Tuple[int, int]:
    row, _ = ctx.position

    def cont() -> Iterator[int]:
        for e in chain((edit,), edits):
            if isinstance(e, ContextualEdit):
                lo = row - (len(e.old_prefix.split(ctx.linefeed)) - 1)
                hi = row + (len(e.old_suffix.split(ctx.linefeed)) - 1)
                yield from (lo, hi)

            elif isinstance(e, RangeEdit):
                (lo, _), (hi, _) = e.begin, e.end
                yield from (lo, hi)

            elif isinstance(e, Edit):
                yield row

            else:
                never(e)

    line_nums = tuple(cont())
    return min(line_nums), max(line_nums) + 1


def _contextual_edit_trans(
    ctx: Context, lines: _Lines, edit: ContextualEdit
) -> EditInstruction:
    row, col = ctx.position
    old_prefix_lines = edit.old_prefix.split(ctx.linefeed)
    old_suffix_lines = edit.old_suffix.split(ctx.linefeed)

    r1 = row - (len(old_prefix_lines) - 1)
    r2 = row + (len(old_suffix_lines) - 1)

    c1 = (
        lines.len8[r1] - len(encode(old_prefix_lines[0]))
        if len(old_prefix_lines) > 1
        else col - len(encode(old_prefix_lines[0]))
    )
    c2 = (
        len(encode(old_suffix_lines[-1]))
        if len(old_prefix_lines) > 1
        else col + len(encode(old_suffix_lines[0]))
    )

    begin = r1, c1
    end = r2, c2

    new_lines = edit.new_text.split(ctx.linefeed)
    new_prefix_lines = edit.new_prefix.split(ctx.linefeed)
    cursor_yoffset = -len(old_prefix_lines) + len(new_prefix_lines)
    cursor_xpos = (
        len(encode(new_prefix_lines[-1]))
        if len(new_prefix_lines) > 1
        else len(encode(ctx.line_before))
        - len(encode(old_prefix_lines[-1]))
        + len(encode(new_prefix_lines[0]))
    )

    inst = EditInstruction(
        primary=True,
        begin=begin,
        end=end,
        cursor_yoffset=cursor_yoffset,
        cursor_xpos=cursor_xpos,
        new_lines=new_lines,
    )
    return inst


def _edit_trans(
    unifying_chars: AbstractSet[str],
    ctx: Context,
    lines: _Lines,
    edit: Edit,
) -> EditInstruction:

    adjusted = trans_adjusted(unifying_chars, ctx=ctx, new_text=edit.new_text)
    inst = _contextual_edit_trans(ctx, lines=lines, edit=adjusted)
    return inst


def _range_edit_trans(
    unifying_chars: AbstractSet[str],
    ctx: Context,
    primary: bool,
    lines: _Lines,
    edit: RangeEdit,
) -> EditInstruction:
    new_lines = edit.new_text.split(ctx.linefeed)

    if (
        primary
        and not isinstance(edit, ParsedEdit)
        and len(new_lines) <= 1
        and edit.begin == edit.end
    ):
        return _edit_trans(unifying_chars, ctx=ctx, lines=lines, edit=edit)

    else:
        (r1, ec1), (r2, ec2) = sorted((edit.begin, edit.end))

        if edit.encoding == UTF16:
            c1 = len(encode(decode(lines.b_lines16[r1][: ec1 * 2], encoding=UTF16)))
            c2 = len(encode(decode(lines.b_lines16[r2][: ec2 * 2], encoding=UTF16)))
        elif edit.encoding == UTF8:
            c1 = len(lines.b_lines8[r1][:ec1])
            c2 = len(lines.b_lines8[r2][:ec2])
        else:
            raise ValueError(f"Unknown encoding -- {edit.encoding}")

        begin = r1, c1
        end = r2, c2

        lines_before = (
            edit.new_prefix.split(ctx.linefeed)
            if isinstance(edit, ParsedEdit)
            else new_lines
        )
        cursor_yoffset = (r2 - r1) + (len(lines_before) - 1)
        cursor_xpos = (
            (
                len(encode(lines_before[-1]))
                if len(lines_before) > 1
                else len(lines.b_lines8[r2][:c1]) + len(encode(lines_before[0]))
            )
            if primary
            else -1
        )

        inst = EditInstruction(
            primary=primary,
            begin=begin,
            end=end,
            cursor_yoffset=cursor_yoffset,
            cursor_xpos=cursor_xpos,
            new_lines=new_lines,
        )
        return inst


def _instructions(
    ctx: Context,
    unifying_chars: AbstractSet[str],
    lines: _Lines,
    primary: Edit,
    secondary: Sequence[RangeEdit],
) -> Iterator[EditInstruction]:
    if isinstance(primary, RangeEdit):
        inst = _range_edit_trans(
            unifying_chars,
            ctx=ctx,
            primary=True,
            lines=lines,
            edit=primary,
        )
        yield inst

    elif isinstance(primary, ContextualEdit):
        inst = _contextual_edit_trans(ctx, lines=lines, edit=primary)
        yield inst

    elif isinstance(primary, Edit):
        inst = _edit_trans(unifying_chars, ctx=ctx, lines=lines, edit=primary)
        yield inst

    else:
        never(primary)

    for edit in secondary:
        yield _range_edit_trans(
            unifying_chars,
            ctx=ctx,
            primary=False,
            lines=lines,
            edit=edit,
        )


def _consolidate(
    instruction: EditInstruction, *instructions: EditInstruction
) -> Sequence[EditInstruction]:
    edits = sorted(chain((instruction,), instructions), key=lambda i: (i.begin, i.end))
    pivot = 0, 0
    stack: MutableSequence[EditInstruction] = []

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


def _shift(instructions: Iterable[EditInstruction]) -> Iterator[EditInstruction]:
    row_shift = 0
    col_shift: MutableMapping[int, int] = {}

    for inst in instructions:
        (r1, c1), (r2, c2) = inst.begin, inst.end
        yield EditInstruction(
            primary=inst.primary,
            begin=(r1 + row_shift, c1 + col_shift.get(r1, 0)),
            end=(r2 + row_shift, c2 + col_shift.get(r2, 0)),
            cursor_yoffset=inst.cursor_yoffset,
            cursor_xpos=inst.cursor_xpos,
            new_lines=inst.new_lines,
        )
        row_shift += (r2 - r1) + len(inst.new_lines) - 1
        f_length = len(encode(inst.new_lines[-1])) if inst.new_lines else 0
        col_shift[r2] = -(c2 - c1) + f_length if r1 == r2 else -c2 + f_length


def apply(nvim: Nvim, buf: Buffer, instructions: Iterable[EditInstruction]) -> None:
    for inst in _shift(instructions):
        try:
            buf_set_text(
                nvim, buf=buf, begin=inst.begin, end=inst.end, text=inst.new_lines
            )
        except NvimError as e:
            tpl = """
            ${e}
            ${inst}
            """
            msg = Template(dedent(tpl)).substitute(e=e, inst=inst)
            log.warn(f"%s", msg)


def _cursor(cursor: NvimPos, instructions: Iterable[EditInstruction]) -> NvimPos:
    row, _ = cursor
    col = -1

    for inst in instructions:
        row += inst.cursor_yoffset
        col = inst.cursor_xpos
        if inst.primary:
            break

    assert col != -1
    return row, col


def _parse(
    nvim: Nvim, buf: Buffer, stack: Stack, state: State, comp: Completion
) -> Tuple[Edit, Sequence[Mark]]:
    if isinstance(comp.primary_edit, SnippetEdit):
        comment_str = buf_commentstr(nvim, buf=buf)
        clipboard = nvim.funcs.getreg()
        info = ParseInfo(visual="", clipboard=clipboard, comment_str=comment_str)
        if isinstance(comp.primary_edit, SnippetRangeEdit):
            row, col = comp.primary_edit.begin
            line, *_ = buf_get_lines(nvim, buf=buf, lo=row, hi=row + 1)
            line_before = decode(
                encode(line, encoding=comp.primary_edit.encoding)[:col]
            )
            edit, marks = parse_range(
                context=state.context, snippet=comp.primary_edit, info=info
            )
        else:
            edit, marks = parse_norm(
                stack.settings.match.unifying_chars,
                context=state.context,
                snippet=comp.primary_edit,
                info=info,
            )
    else:
        edit, marks = comp.primary_edit, ()

    return edit, marks


def _restore(nvim: Nvim, win: Window, buf: Buffer, pos: NvimPos) -> Tuple[str, int]:
    row, _ = pos
    ns = create_ns(nvim, ns=NS)
    marks = tuple(buf_get_extmarks(nvim, buf=buf, id=ns))
    if len(marks) != 2:
        return "", 0
    else:
        m1, m2 = marks
        after, *_ = buf_get_lines(nvim, buf=buf, lo=row, hi=row + 1)
        cur_row, cur_col = win_get_cursor(nvim, win=win)

        (_, lo), (_, hi) = m1.end, m2.begin

        binserted = encode(after)[lo:hi]
        inserted = decode(binserted)

        if inserted and cur_row == row and lo <= cur_col <= hi:
            movement = cur_col - lo
        else:
            movement = len(binserted)

        if inserted:
            buf_set_text(nvim, buf=buf, begin=m1.end, end=m2.begin, text=("",))

        return inserted, movement


def edit(
    nvim: Nvim, stack: Stack, state: State, metric: Metric, synthetic: bool
) -> Optional[Tuple[int, int]]:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    if buf.number != state.context.buf_id:
        log.warn("%s", "stale buffer")
        return None
    else:
        nvim.options["undolevels"] = nvim.options["undolevels"]

        if synthetic:
            inserted, movement = "", 0
        else:
            inserted, movement = _restore(
                nvim, win=win, buf=buf, pos=state.context.position
            )

        try:
            primary, marks = _parse(
                nvim, buf=buf, stack=stack, state=state, comp=metric.comp
            )
        except (NvimError, ParseError) as e:
            primary, marks = metric.comp.primary_edit, ()
            write(nvim, LANG("failed to parse snippet"))
            log.info("%s", e)

        lo, hi = _rows_to_fetch(
            state.context,
            primary,
            *metric.comp.secondary_edits,
        )
        if lo < 0 or hi > state.context.line_count:
            log.warn("%s", pformat(("OUT OF BOUNDS", (lo, hi), metric)))
            return None
        else:
            limited_lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)
            lines = [*chain(repeat("", times=lo), limited_lines)]
            view = _lines(lines)

            instructions = _consolidate(
                *_instructions(
                    state.context,
                    unifying_chars=stack.settings.match.unifying_chars,
                    lines=view,
                    primary=primary,
                    secondary=metric.comp.secondary_edits,
                )
            )
            n_row, p_col = _cursor(
                state.context.position,
                instructions=instructions,
            )
            n_col = p_col + movement

            if not synthetic:
                stack.idb.inserted(metric.instance.bytes, sort_by=metric.comp.sort_by)

            apply(nvim, buf=buf, instructions=instructions)
            if inserted:
                try:
                    buf_set_text(
                        nvim,
                        buf=buf,
                        begin=(n_row, p_col),
                        end=(n_row, p_col),
                        text=(inserted,),
                    )
                except NvimError as e:
                    log.warn("%s", e)

            try:
                win_set_cursor(nvim, win=win, row=n_row, col=n_col)
            except NvimError as e:
                log.warn("%s", e)

            if marks:
                mark(nvim, settings=stack.settings, buf=buf, marks=marks)

            if DEBUG:
                log.debug(
                    "%s",
                    pformat(
                        (
                            (metric.comp.primary_edit, *metric.comp.secondary_edits),
                            instructions,
                        )
                    ),
                )
            return n_row, n_col
