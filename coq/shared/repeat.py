from .types import Edit, RangeEdit, SnippetEdit


def sanitize(edit: Edit) -> Edit:
    if isinstance(edit, SnippetEdit):
        return SnippetEdit(grammar=edit.grammar, new_text=edit.new_text)
    elif isinstance(edit, RangeEdit):
        return Edit(new_text=edit.fallback)
    else:
        return Edit(new_text=edit.new_text)
