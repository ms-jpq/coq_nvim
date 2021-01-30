from dataclasses import dataclass
from typing import Annotated, Iterable, Iterator, Sequence, Tuple, Union

from pynvim_pp.text_object import SplitCtx
from std2.types import never
from itertools import accumulate, islice

from ...shared.protocol.types import (
    ApplicableEdit,
    ContextualEdit,
    Edit,
    NvimPos,
    OffsetEncoding,
    RangeEdit,
)

_IText = Union[str, Tuple[()]]
_TextStream = Sequence[_IText]


@dataclass(frozen=True)
class _EditInstruction:
    begin: int
    end: int
    replacement: bytes
    cursor: Annotated[bool, "only one instruction can place cursor"]


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


def _compute_instructions(
    encoding: OffsetEncoding,
    pos: NvimPos,
    ctx: SplitCtx,
    lines: Sequence[str],
    primary: ApplicableEdit,
    *secondary: RangeEdit
) -> Sequence[_EditInstruction]:
    coding = "UTF-16-LE" if encoding is OffsetEncoding.utf_16 else "UTF-8"
    (row, _), col = pos, len(ctx.lhs.encode(coding))

    b_lines = tuple((line.encode(coding) for line in lines))
    lengths = tuple(map(len, b_lines))

    def c1() -> _EditInstruction:
        replacement = primary.new_text.encode(coding)
        if isinstance(primary, Edit):
            below = sum(lengths[:row])
            begin = (
                below + len(ctx.lhs.encode(coding)) - len(ctx.word_lhs.encode(coding))
            )
            end = begin + len(ctx.word_rhs.encode(coding))

        elif isinstance(primary, ContextualEdit):
            below = sum(lengths[:row])
            begin = below + len()
            end = 2

        elif isinstance(primary, RangeEdit):
            begin = 2 + len()
            end = 2

        else:
            never(primary)

        instruction = _EditInstruction(
            begin=begin,
            end=end,
            replacement=replacement,
            cursor=True,
        )
        return instruction

    def c2() -> Iterator[_EditInstruction]:
        pass
