from pynvim import Nvim

from ..shared.types import ContextualEdit, EditEnv, SnippetEdit


def parse(nvim: Nvim, env: EditEnv, snippet: SnippetEdit) -> ContextualEdit:
    edit = ContextualEdit(new_text=snippet.new_text, old_prefix="", new_prefix="")
    return edit

