from itertools import accumulate
from typing import AbstractSet

from .parse import is_word, lower
from .types import Context, ContextualEdit, Edit


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


def trans_adjusted(
    unifying_chars: AbstractSet[str], ctx: Context, edit: Edit
) -> ContextualEdit:
    c_edit = trans(line_before=ctx.line_before, line_after=ctx.line_after, edit=edit)
    old_prefix = c_edit.old_prefix or (
        ctx.words_before
        if is_word(c_edit.new_text[:1], unifying_chars=unifying_chars)
        else ctx.words_before + ctx.syms_before
    )
    old_suffix = c_edit.old_suffix or (
        ctx.words_after
        if is_word(c_edit.new_text[-1:], unifying_chars=unifying_chars)
        else ctx.words_after + ctx.syms_after
    )
    adjusted = ContextualEdit(
        new_text=c_edit.new_text,
        new_prefix=c_edit.new_text,
        old_prefix=old_prefix,
        old_suffix=old_suffix,
    )
    return adjusted


def expand_tabs(context: Context, text: str) -> str:

    new_text = (
        text.replace("\t", " " * context.tabstop)
        if context.expandtab
        else text.replace(" " * context.tabstop, "\t")
    )
    return new_text

