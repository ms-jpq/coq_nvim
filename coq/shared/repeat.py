from typing import Optional

from .types import Edit, RangeEdit, SnippetEdit


def sanitize(edit: Edit) -> Optional[Edit]:
    if isinstance(edit, RangeEdit):
        return Edit(new_text=edit.fallback)
    elif isinstance(edit, SnippetEdit):
        return edit
    else:
        return Edit(new_text=edit.new_text)
