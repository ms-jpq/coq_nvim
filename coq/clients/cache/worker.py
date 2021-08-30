from dataclasses import dataclass, replace
from typing import Awaitable, Callable, Iterator, MutableMapping, Sequence, Tuple
from uuid import UUID, uuid4

from ...shared.runtime import Supervisor
from ...shared.timeit import timeit
from ...shared.types import Completion, Context, Edit, SnippetEdit
from .database import Database


@dataclass(frozen=True)
class _CacheCtx:
    change_id: UUID
    commit_id: UUID
    buf_id: int
    row: int
    line_before: str


def _use_cache(cache: _CacheCtx, ctx: Context) -> bool:
    row, _ = ctx.position
    use_cache = (
        cache.commit_id == ctx.commit_id
        and ctx.buf_id == cache.buf_id
        and row == cache.row
        and ctx.line_before.startswith(cache.line_before)
    )
    return use_cache


def sanitze_cached(comp: Completion) -> Completion:
    p_edit = comp.primary_edit
    if isinstance(p_edit, SnippetEdit):
        edit = SnippetEdit(grammar=p_edit.grammar, new_text=p_edit.new_text)
    else:
        edit = Edit(new_text=p_edit.new_text)
    return replace(comp, primary_edit=edit, secondary_edits=())


class CacheWorker:
    def __init__(self, supervisor: Supervisor) -> None:
        self._soup = supervisor
        self._db = Database(supervisor.pool)
        self._cache_ctx = _CacheCtx(
            change_id=uuid4(),
            commit_id=uuid4(),
            buf_id=-1,
            row=-1,
            line_before="",
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
            line_before=context.line_before[: -len(context.syms_before)],
        )
        use_cache = _use_cache(cache_ctx, ctx=context) and bool(self._cached)
        if not use_cache:
            self._cached.clear()

        async def get() -> Iterator[Completion]:
            with timeit("CACHE -- GET"):
                match = context.words_before or context.syms_before
                words = await self._db.select(
                    not use_cache,
                    options=self._soup.options,
                    word=match,
                    limitless=context.manual,
                )
                comps = (self._cached.get(sort_by) for sort_by in words)
                return (sanitze_cached(c) for c in comps if c)

        async def set(completions: Sequence[Completion]) -> None:
            new_comps = {c.sort_by: c for c in completions}
            await self._db.insert(new_comps.keys())
            self._cached.update(new_comps)

        return use_cache, get(), set
