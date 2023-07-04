from dataclasses import replace
from typing import Optional, Tuple

from std2.types import never

from .types import (
    UTF8,
    UTF16,
    UTF32,
    BaseRangeEdit,
    Cursors,
    Edit,
    RangeEdit,
    SnippetEdit,
    SnippetRangeEdit,
    WTF8Pos,
)


def _whitespaced(text: str) -> bool:
    return any(c.isspace() for c in text)


def _shift(cursors: Cursors, edit: BaseRangeEdit) -> Tuple[WTF8Pos, WTF8Pos]:
    row, u8, u16, u32 = cursors
    if edit.encoding == UTF16:
        col = u16
    elif edit.encoding == UTF8:
        col = u8
    elif edit.encoding == UTF32:
        col = u32
    else:
        never(edit.encoding)

    prev_col = edit.cursor_pos
    (b_row, b_col), (e_row, e_col) = edit.begin, edit.end
    diff = col - prev_col

    if b_row == row:
        if b_col >= prev_col:
            new_b_col = b_col + diff
        else:
            new_b_col = b_col
    else:
        new_b_col = b_col

    if e_row == row:
        if e_col >= prev_col:
            new_e_col = e_col + diff
        else:
            new_e_col = e_col
    else:
        new_e_col = e_col

    return (b_row, new_b_col), (e_row, new_e_col)


def sanitize(cursors: Cursors, edit: Edit) -> Optional[Edit]:
    row, *_ = cursors
    if isinstance(edit, SnippetRangeEdit):
        if row == -1:
            if edit.fallback == edit.new_text:
                return SnippetEdit(grammar=edit.grammar, new_text=edit.new_text)
            else:
                return None
        elif not _whitespaced(edit.new_text):
            if fallback := edit.fallback:
                return SnippetEdit(grammar=edit.grammar, new_text=fallback)
            else:
                return None
        else:
            begin, end = _shift(cursors, edit=edit)
            return replace(edit, begin=begin, end=end)
    elif isinstance(edit, RangeEdit):
        if row == -1:
            if edit.begin == edit.end:
                return Edit(new_text=edit.new_text)
            else:
                return None
        elif not _whitespaced(edit.new_text):
            return Edit(new_text=edit.fallback)
        else:
            begin, end = _shift(cursors, edit=edit)
            return replace(edit, begin=begin, end=end)
    elif isinstance(edit, SnippetEdit):
        return edit
    else:
        return Edit(new_text=edit.new_text)
