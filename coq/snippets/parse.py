from ..shared.types import ContextualEdit, SnippetEdit


def parse(snippet: SnippetEdit) -> ContextualEdit:
    edit = ContextualEdit(new_text=snippet.new_text, old_prefix="", new_prefix="")
    return edit
