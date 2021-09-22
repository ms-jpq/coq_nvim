from itertools import accumulate
from typing import AbstractSet

from .context import cword_after, cword_before
from .parse import coalesce, lower
from .types import Context, ContextualEdit


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


def trans(line_before: str, line_after: str, new_text: str) -> ContextualEdit:
    l_match = _match(True, existing=line_before, insertion=new_text)
    rest = new_text[len(l_match) :]
    r_match = _match(False, existing=line_after, insertion=rest)
    c_edit = ContextualEdit(
        new_text=new_text,
        new_prefix=new_text,
        old_prefix=line_before[-len(l_match) :] if l_match else "",
        old_suffix=line_after[: len(r_match)],
    )
    return c_edit


def trans_adjusted(
    unifying_chars: AbstractSet[str], ctx: Context, new_text: str
) -> ContextualEdit:
    edit = trans(
        line_before=ctx.line_before, line_after=ctx.line_after, new_text=new_text
    )
    new_syms = len(tuple(coalesce(new_text, unifying_chars=unifying_chars)))
    simple_before = cword_before(
        unifying_chars, lower=False, context=ctx, sort_by=edit.new_text
    )
    simple_after = cword_after(
        unifying_chars, lower=False, context=ctx, sort_by=edit.new_text
    )

    old_prefix = simple_before if new_syms <= 1 else (edit.old_prefix or simple_before)
    old_suffix = simple_after if new_syms <= 1 else (edit.old_suffix or simple_after)

    adjusted = ContextualEdit(
        new_text=edit.new_text,
        new_prefix=edit.new_prefix,
        old_prefix=old_prefix,
        old_suffix=old_suffix,
    )
    return adjusted


def expand_tabs(context: Context, text: str) -> str:
    new_text = (
        text.expandtabs(context.tabstop)
        if context.expandtab
        else text.replace(" " * context.tabstop, "\t")
    )
    return new_text
