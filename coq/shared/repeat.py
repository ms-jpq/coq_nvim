from typing import Optional

from ..lsp.types import Cursors
from .types import Edit, RangeEdit, SnippetEdit, SnippetRangeEdit


def sanitize(cursors: Optional[Cursors], edit: Edit) -> Optional[Edit]:
    if isinstance(edit, SnippetRangeEdit):
        if (
            not edit.fallback
            or edit.begin == edit.end
            or edit.fallback == edit.new_text
        ):
            return SnippetEdit(grammar=edit.grammar, new_text=edit.new_text)
        else:
            return Edit(new_text=edit.fallback)
    elif isinstance(edit, SnippetEdit):
        return edit
    elif isinstance(edit, RangeEdit):
        if edit.begin == edit.end:
            return Edit(new_text=edit.fallback)
        else:
            return edit
    else:
        return Edit(new_text=edit.new_text)
