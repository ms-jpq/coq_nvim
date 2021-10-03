from dataclasses import dataclass, replace
from typing import (
    AbstractSet,
    Awaitable,
    Callable,
    Iterator,
    MutableMapping,
    Optional,
    Sequence,
    Tuple,
)
from uuid import UUID, uuid4

from pynvim_pp.text_object import gen_split

from ...shared.fuzzy import multi_set_ratio
from ...shared.parse import lower
from ...shared.repeat import sanitize
from ...shared.runtime import Supervisor
from ...shared.settings import MatchOptions
from ...shared.timeit import timeit
from ...shared.trans import cword_before, l_match
from ...shared.types import Completion, Context, Edit, SnippetEdit
from .database import Database


@dataclass(frozen=True)
class _CacheCtx:
    change_id: UUID
    commit_id: UUID
    buf_id: int
    row: int
    text_before: str


def _use_cache(cache: _CacheCtx, ctx: Context) -> bool:
    row, _ = ctx.position
    use_cache = (
        not ctx.manual
        and cache.commit_id == ctx.commit_id
        and ctx.buf_id == cache.buf_id
        and row == cache.row
        and ctx.syms_before.startswith(cache.text_before)
    )
    return use_cache


def sanitize_cached(comp: Completion) -> Completion:
    edit = sanitize(comp.primary_edit)
    cached = replace(comp, primary_edit=edit, secondary_edits=())
    return cached


def use_comp(match: MatchOptions, context: Context, sort_by: str, edit: Edit) -> bool:
    cword = cword_before(
        match.unifying_chars,
        lower=True,
        context=context,
        sort_by=sort_by,
    )
    if len(sort_by) + match.look_ahead >= len(cword):
        ratio = multi_set_ratio(
            cword,
            lower(sort_by),
            look_ahead=match.look_ahead,
        )
        use = ratio >= match.fuzzy_cutoff and (
            isinstance(edit, SnippetEdit) or not cword.startswith(edit.new_text)
        )
        return use
    else:
        return False


def _hard_sortby(
    unifying_chars: AbstractSet[str], context: Context, sort_by: str
) -> Optional[str]:
    if (lhs := l_match(context.line_before, sort_by=sort_by)) and (
        rhs := sort_by[len(lhs) :]
    ):
        split = gen_split(lhs=lhs, rhs=rhs, unifying_chars=unifying_chars)
        if context.ws_before:
            return split.ws_lhs + split.ws_rhs
        elif context.syms_before != context.words_before:
            return split.syms_lhs + split.syms_rhs
        else:
            return split.word_lhs + split.word_rhs
    else:
        return None


class CacheWorker:
    def __init__(self, supervisor: Supervisor) -> None:
        self._soup = supervisor
        self._db = Database(supervisor.pool)
        self._cache_ctx = _CacheCtx(
            change_id=uuid4(),
            commit_id=uuid4(),
            buf_id=-1,
            row=-1,
            text_before="",
        )
        self._cached: MutableMapping[str, Completion] = {}

    def _use_cache(
        self, enable_correction: bool, context: Context
    ) -> Tuple[
        bool,
        Awaitable[Iterator[Completion]],
        Callable[[Sequence[Completion]], Awaitable[None]],
    ]:
        cache_ctx = self._cache_ctx
        row, _ = context.position
        self._cache_ctx = _CacheCtx(
            change_id=context.change_id,
            commit_id=context.commit_id,
            buf_id=context.buf_id,
            row=row,
            text_before=context.syms_before,
        )
        use_cache = _use_cache(cache_ctx, ctx=context) and bool(self._cached)
        if not use_cache:
            self._cached.clear()

        async def get() -> Iterator[Completion]:
            with timeit("CACHE -- GET"):
                words = await self._db.select(
                    not use_cache,
                    opts=self._soup.match,
                    word=context.words,
                    sym=context.syms,
                    limitless=context.manual,
                )
                if enable_correction and not words:

                    def cont() -> Iterator[Completion]:
                        for comp in tuple(self._cached.values()):
                            if sort_by := _hard_sortby(
                                self._soup.match.unifying_chars,
                                context=context,
                                sort_by=comp.sort_by,
                            ):
                                if use_comp(
                                    self._soup.match,
                                    context=context,
                                    sort_by=sort_by,
                                    edit=comp.primary_edit,
                                ):
                                    new_comp = sanitize_cached(
                                        replace(comp, sort_by=sort_by)
                                    )
                                    yield new_comp

                    comps = cont()
                else:
                    comps = (
                        sanitize_cached(comp)
                        for sort_by in words
                        if (comp := self._cached.get(sort_by))
                    )
                return comps

        async def set_cache(completions: Sequence[Completion]) -> None:
            new_comps = {comp.sort_by: comp for comp in completions}
            await self._db.insert(new_comps.keys())
            self._cached.update(new_comps)

        return use_cache, get(), set_cache
