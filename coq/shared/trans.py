from itertools import accumulate

from .parse import lower
from .types import ContextualEdit, Edit, EditEnv


def _match(lhs: bool, existing: str, insertion: str) -> str:
    existing, insertion = lower(existing), lower(insertion)
    if lhs:
        for match in reversed(tuple(accumulate(insertion))):
            if match == existing[-len(match) :]:
                return match
        else:
            return ""
    else:
        for match in reversed(tuple(accumulate(reversed(insertion)))):
            if match == existing[: len(match) :]:
                return match
        else:
            return ""


def trans(line_before: str, line_after: str, edit: Edit) -> ContextualEdit:
    l_match = _match(True, existing=line_before, insertion=edit.new_text)
    rest = edit.new_text[len(l_match) :]
    r_match = _match(False, existing=line_after, insertion=rest)
    c_edit = ContextualEdit(
        new_text=edit.new_text,
        new_prefix=edit.new_text,
        old_prefix=line_before[-len(l_match) :] if l_match else "",
        old_suffix=line_after[: len(r_match)],
    )
    return c_edit


def expand_tabs(env: EditEnv, text: str) -> str:

    new_text = (
        text.replace("\t", " " * env.tabstop)
        if env.expandtab
        else text.replace(" " * env.tabstop, "\t")
    )
    return new_text

