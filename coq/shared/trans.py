from itertools import chain, repeat
from typing import AbstractSet, Iterable, Iterator

from pynvim_pp.text_object import is_word

from .context import cword_after, cword_before
from .parse import coalesce, lower
from .types import Context, ContextualEdit


def reverse_acc(replace_prefix_threshold: int, seq: str) -> Iterator[str]:
    def cont() -> Iterator[str]:
        yield seq
        for i in range(1, len(seq)):
            yield seq[:-i]

    for sub in cont():
        if sub and len(sub) >= replace_prefix_threshold:
            yield sub


def _line_match(
    replace_prefix_threshold: int,
    unifying_chars: AbstractSet[str],
    lhs: bool,
    existing: str,
    insertion: str,
) -> str:
    existing, insertion = lower(existing), lower(insertion)
    if lhs:
        prefix = next(
            coalesce(insertion, unifying_chars=unifying_chars, include_syms=True), ""
        )
        for match in reverse_acc(0, seq=insertion):
            if match == existing[-len(match) :]:
                if match == prefix or len(match) >= replace_prefix_threshold:
                    return match
        else:
            return ""
    else:
        for match in reverse_acc(
            replace_prefix_threshold, seq="".join(reversed(insertion))
        ):
            if match == existing[: len(match) :][::-1]:
                return match
        else:
            return ""


def trans(
    replace_prefix_threshold: int,
    unifying_chars: AbstractSet[str],
    line_before: str,
    line_after: str,
    new_text: str,
) -> ContextualEdit:
    l_match = _line_match(
        replace_prefix_threshold,
        unifying_chars=unifying_chars,
        lhs=True,
        existing=line_before,
        insertion=new_text,
    )
    rest = new_text[len(l_match) :]
    r_match = _line_match(
        replace_prefix_threshold,
        unifying_chars=unifying_chars,
        lhs=False,
        existing=line_after,
        insertion=rest,
    )
    edit = ContextualEdit(
        new_text=new_text,
        new_prefix=new_text,
        old_prefix=line_before[-len(l_match) :] if l_match else "",
        old_suffix=line_after[: len(r_match)] if r_match else "",
    )
    return edit


def trans_adjusted(
    unifying_chars: AbstractSet[str],
    replace_prefix_threshold: int,
    ctx: Context,
    new_text: str,
) -> ContextualEdit:
    edit = trans(
        replace_prefix_threshold,
        unifying_chars=unifying_chars,
        line_before=ctx.line_before,
        line_after=ctx.line_after,
        new_text=new_text,
    )

    simple_before = cword_before(
        unifying_chars, lower=False, context=ctx, sort_by=edit.new_text
    )
    simple_after = cword_after(
        unifying_chars, lower=False, context=ctx, sort_by=edit.new_text
    )

    tokens = len(
        tuple(coalesce(new_text, unifying_chars=unifying_chars, include_syms=True))
    )
    old_prefix = (
        simple_before
        if tokens <= 1
        else edit.old_prefix
        or (
            simple_before
            if is_word(simple_before, unifying_chars=unifying_chars)
            else ""
        )
    )
    old_suffix = simple_after if tokens <= 1 else edit.old_suffix

    adjusted = ContextualEdit(
        new_text=edit.new_text,
        new_prefix=edit.new_prefix,
        old_prefix=old_prefix,
        old_suffix=old_suffix,
    )
    return adjusted


def expand_tabs(context: Context, text: str) -> str:
    spaces = " " * context.tabstop
    new_text = (
        text.replace("\t", spaces) if context.expandtab else text.replace(spaces, "\t")
    )
    return new_text


def _indent_to_line(context: Context, line_before: str) -> str:
    indent_len = len(line_before)
    indent = (
        " " * indent_len
        if context.expandtab
        else (" " * indent_len).replace(" " * context.tabstop, "\t")
    )
    return indent


def indent_adjusted(
    context: Context, line_before: str, lines: Iterable[str]
) -> Iterator[str]:
    indent = _indent_to_line(context, line_before=line_before)
    expanded = (expand_tabs(context, text=line) for line in lines)
    for lhs, rhs in zip(chain(("",), repeat(indent)), expanded):
        yield lhs + rhs
