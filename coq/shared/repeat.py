from typing import Optional, Tuple

from ..lsp.types import Cursors
from .types import BaseRangeEdit, Edit, RangeEdit, SnippetEdit, SnippetRangeEdit


def _shift(edit: BaseRangeEdit) -> Tuple[int, int, int, int]:
    return 0, 0, 0, 0


def sanitize(cursors: Optional[Cursors], edit: Edit) -> Optional[Edit]:
    if isinstance(edit, SnippetRangeEdit):
        if not edit.fallback or edit.fallback == edit.new_text:
            return SnippetEdit(grammar=edit.grammar, new_text=edit.new_text)
        else:
            return Edit(new_text=edit.fallback)
    elif isinstance(edit, SnippetEdit):
        return edit
    elif isinstance(edit, RangeEdit):
        if edit.begin == edit.end:
            return edit
        else:
            return Edit(new_text=edit.fallback)
    else:
        return Edit(new_text=edit.new_text)
