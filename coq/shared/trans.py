from itertools import chain, repeat
from typing import AbstractSet, Iterable, Iterator

from pynvim_pp.text_object import is_word

from ..shared.settings import CompleteOptions, MatchOptions
from .context import cword_after, cword_before
from .fuzzy import multi_set_ratio
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
            coalesce(
                unifying_chars, include_syms=True, backwards=False, chars=insertion
            ),
            "",
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
    replace_suffix_threshold: int,
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
        replace_suffix_threshold,
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
    match: MatchOptions,
    comp: CompleteOptions,
    ctx: Context,
    new_text: str,
) -> ContextualEdit:
    edit = trans(
        comp.replace_prefix_threshold,
        replace_suffix_threshold=comp.replace_suffix_threshold,
        unifying_chars=match.unifying_chars,
        line_before=ctx.line_before,
        line_after=ctx.line_after,
        new_text=new_text,
    )

    tokens = tuple(
        coalesce(
            match.unifying_chars, include_syms=True, backwards=False, chars=new_text
        )
    )

    if len(edit.old_prefix) >= comp.replace_prefix_threshold:
        old_prefix = edit.old_prefix
    elif ctx.syms_before and edit.new_text.startswith(ctx.syms_before):
        old_prefix = ctx.syms_before
    elif ctx.words_before and edit.new_text.startswith(ctx.words_before):
        old_prefix = ctx.words_before
    elif len(tokens) <= 1:
        simple_before = cword_before(
            match.unifying_chars, lower=False, context=ctx, sort_by=edit.new_text
        )
        old_prefix = simple_before
    elif edit.old_prefix:
        old_prefix = edit.old_prefix
    elif chr := next(chain.from_iterable(tokens), ""):
        if is_word(match.unifying_chars, chr=chr):
            old_prefix = (
                ctx.words_before
                if multi_set_ratio(
                    ctx.words_before, new_text, look_ahead=match.look_ahead
                )
                >= match.fuzzy_cutoff
                else ""
            )
        else:
            old_prefix = (
                ctx.syms_before
                if multi_set_ratio(
                    ctx.syms_before, new_text, look_ahead=match.look_ahead
                )
                >= match.fuzzy_cutoff
                else ""
            )
    else:
        old_prefix = ""

    if len(edit.old_suffix) >= comp.replace_suffix_threshold:
        old_suffix = edit.old_suffix
    elif len(tokens) <= 1:
        simple_after = cword_after(
            match.unifying_chars, lower=False, context=ctx, sort_by=edit.new_text
        )
        old_suffix = simple_after
    else:
        old_suffix = edit.old_suffix

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
        if rhs:
            yield lhs + rhs
        else:
            yield rhs
