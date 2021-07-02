from dataclasses import dataclass, replace
from typing import Iterator, Mapping, Optional, Sequence, Tuple

from ...shared.runtime import Supervisor
from ...shared.types import Completion, Context, Edit
from .database import Database


@dataclass(frozen=True)
class _CacheCtx:
    buf_id: int
    row: int
    line_before: str
    comps: Mapping[str, Completion]


def _use_cache(cache: _CacheCtx, ctx: Context) -> bool:
    row, _ = ctx.position
    return (
        len(cache.comps) > 0
        and ctx.pum_visible
        and ctx.buf_id == cache.buf_id
        and row == cache.row
        and ctx.line_before.startswith(cache.line_before)
    )


def _cachin(comp: Completion) -> Tuple[str, Completion]:
    p_edit = comp.primary_edit
    sort_by = comp.sort_by or p_edit.new_text
    edit = p_edit if type(p_edit) is Edit else Edit(new_text=p_edit.new_text)
    return sort_by, replace(comp, primary_edit=edit, secondary_edits=())


class CacheWorker:
    def __init__(self, supervisor: Supervisor) -> None:
        self._soup = supervisor
        self._db = Database(supervisor.pool)
        self._cache_ctx = _CacheCtx(buf_id=-1, row=-1, line_before="", comps={})

    def _use_cache(self, context: Context) -> Optional[Sequence[Completion]]:
        if _use_cache(self._cache_ctx, ctx=context):
            match = context.words or context.syms
            words = self._db.select(self._soup.options, word=match)

            def cont() -> Iterator[Completion]:
                for word in words:
                    cmp = self._cache_ctx.comps.get(word)
                    if cmp:
                        yield cmp

            return tuple(cont())
        else:
            return None

    def _set_cache(self, context: Context, completions: Sequence[Completion]) -> None:
        row, _ = context.position
        ctx = _CacheCtx(
            buf_id=context.buf_id,
            row=row,
            line_before=context.line_before,
            comps={k: v for k, v in map(_cachin, completions)},
        )
        self._db.add(ctx.comps)
        self._cache_ctx = ctx

