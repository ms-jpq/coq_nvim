from dataclasses import dataclass
from itertools import chain
from typing import Annotated, Iterable, Iterator, MutableSequence, Sequence

from pynvim_pp.text_object import SplitCtx
from std2.ordinal import clamp
from std2.seq import maybe_indexed
from std2.types import never

from ..shared.types import (
    ApplicableEdit,
    ContextualEdit,
    Edit,
    NvimPos,
    RangeEdit,
)


@dataclass(frozen=True)
class _EditInstruction:
    begin: int
    end: int
    replacement: bytes
    is_cursor: Annotated[bool, "only one instruction can place cursor"]


def _rows_to_fetch(pos: NvimPos, edits: Iterable[ApplicableEdit]) -> range:
    row, _ = pos

    def cont() -> Iterator[int]:
        for edit in edits:
            if isinstance(edit, Edit):
                yield row
            elif isinstance(edit, RangeEdit):
                (lo, _), (hi, _) = edit.begin, edit.end
                yield from (lo, hi)
            elif isinstance(edit, ContextualEdit):
                lo = row - len(edit.old_prefix.splitlines())
                hi = row + len(edit.old_suffix.splitlines())
                yield from (lo, hi)
            else:
                never(edit)

    line_nums = tuple(cont())
    return range(start=min(line_nums), stop=max(line_nums) + 1)


def _edit_trans(
    coding: str, pos: NvimPos, ctx: SplitCtx, lengths: Sequence[int], edit: Edit
) -> Iterator[_EditInstruction]:
    (row, _), col = pos, len(ctx.lhs.encode(coding))

    below = sum(lengths[:row])
    begin = below + col - len(ctx.word_lhs.encode(coding))
    end = begin + len(ctx.word_rhs.encode(coding))

    yield _EditInstruction(
        begin=begin,
        end=end,
        replacement=edit.new_text.encode(coding),
        is_cursor=True,
    )


def _contextual_edit_trans(
    coding: str,
    pos: NvimPos,
    ctx: SplitCtx,
    lengths: Sequence[int],
    edit: ContextualEdit,
) -> Iterator[_EditInstruction]:
    (row, _), col = pos, len(ctx.lhs.encode(coding))
    replacement = edit.new_text.encode(coding)

    below = sum(lengths[:row])
    op_l, os_l = len(edit.old_prefix.encode(coding)), len(
        edit.old_suffix.encode(coding)
    )
    begin1 = below + col - op_l
    end1 = begin1 + op_l
    begin2 = end1
    end2 = begin1 + os_l

    yield _EditInstruction(
        begin=begin1,
        end=end1,
        replacement=replacement,
        is_cursor=True,
    )
    yield _EditInstruction(
        begin=begin2,
        end=end2,
        replacement=replacement,
        is_cursor=False,
    )


def _range_edit_trans(
    coding: str, offset_mul: int, lengths: Sequence[int], edit: RangeEdit
) -> Iterator[_EditInstruction]:
    (lo_r, lo_c), (hi_r, hi_c) = sorted((edit.begin, edit.end))
    begin = sum(lengths[:lo_r]) + (
        clamp(0, lo_c, maybe_indexed(lengths, at=lo_r, default=0)) * offset_mul
    )
    end = sum(lengths[:hi_r]) + (
        clamp(0, hi_c, maybe_indexed(lengths, at=hi_r, default=0)) * offset_mul
    )

    yield _EditInstruction(
        begin=begin,
        end=end,
        replacement=edit.new_text.encode(coding),
        is_cursor=True,
    )


def _primary_edit_trans(
    coding: str,
    pos: NvimPos,
    ctx: SplitCtx,
    offset_mul: int,
    lengths: Sequence[int],
    edit: ApplicableEdit,
) -> Iterator[_EditInstruction]:
    if isinstance(edit, Edit):
        yield from _edit_trans(coding, pos=pos, ctx=ctx, lengths=lengths, edit=edit)
    elif isinstance(edit, ContextualEdit):
        yield from _contextual_edit_trans(
            coding, pos=pos, ctx=ctx, lengths=lengths, edit=edit
        )
    elif isinstance(edit, RangeEdit):
        yield from _range_edit_trans(
            coding, offset_mul=offset_mul, lengths=lengths, edit=edit
        )
    else:
        never(edit)


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


def _trans(
    encoding: OffsetEncoding,
    pos: NvimPos,
    ctx: SplitCtx,
    lines: Sequence[str],
    primary: ApplicableEdit,
    *secondary: RangeEdit
) -> str:
    """
    Byte level edits
    """

    coding = "UTF-16-LE" if encoding is OffsetEncoding.utf_16 else "UTF-8"
    offset_mul = 2 if encoding is OffsetEncoding.utf_16 else 1

    b_lines = tuple((line.encode(coding) for line in lines))
    lengths = tuple(map(len, b_lines))

    def cont() -> Iterator[_EditInstruction]:
        yield from _primary_edit_trans(
            coding,
            pos=pos,
            ctx=ctx,
            offset_mul=offset_mul,
            lengths=lengths,
            edit=primary,
        )
        for edit in secondary:
            yield from _range_edit_trans(
                coding, offset_mul=offset_mul, lengths=lengths, edit=edit
            )

    instructions = _consolidate(*cont())
