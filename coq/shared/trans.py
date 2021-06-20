from itertools import accumulate

from .types import ContextualEdit, Edit


def _match(lhs: bool, existing: str, insertion: str) -> str:
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

