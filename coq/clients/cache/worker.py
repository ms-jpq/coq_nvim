from dataclasses import dataclass, replace
from typing import (
    Awaitable,
    Callable,
    Iterator,
    MutableMapping,
    MutableSet,
    Sequence,
    Tuple,
)
from uuid import UUID, uuid4

from ...shared.repeat import sanitize
from ...shared.runtime import Supervisor
from ...shared.timeit import timeit
from ...shared.trans import more_sortby
from ...shared.types import Completion, Context
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


class CacheWorker:
    def __init__(self, supervisor: Supervisor) -> None:
        self._soup = supervisor
        self._db = Database(
            supervisor.pool, unifying_chars=supervisor.options.unifying_chars
        )
        self._cache_ctx = _CacheCtx(
            change_id=uuid4(),
            commit_id=uuid4(),
            buf_id=-1,
            row=-1,
            text_before="",
        )
        self._cached: MutableMapping[str, Completion] = {}

    def _use_cache(
        self, context: Context
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
                    opts=self._soup.options,
                    word=context.words,
                    sym=context.syms,
                    limitless=context.manual,
                )

                def cont() -> Iterator[Completion]:
                    seen: MutableSet[UUID] = set()
                    for sort_by in words:
                        if comp := self._cached.get(sort_by):
                            if comp.uid not in seen:
                                seen.add(comp.uid)
                                yield sanitize_cached(comp)

                return cont()

        async def set_cache(completions: Sequence[Completion]) -> None:
            new_comps: MutableMapping[str, Completion] = {}
            for comp in completions:
                for sort_by in more_sortby(context.line_before, sort_by=comp.sort_by):
                    new_comps[sort_by] = comp

            await self._db.insert(new_comps.keys())
            self._cached.update(new_comps)

        return use_cache, get(), set_cache
