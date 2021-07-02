from concurrent.futures import Executor
from dataclasses import dataclass
from typing import Iterator, Mapping, Optional, Sequence

from ...shared.types import Completion, Context
from .database import Database


@dataclass(frozen=True)
class _CacheCtx:
    buf_id: int
    row: int
    line_before: str
    comps: Mapping[str, Completion]


def _cachin(comp: Completion) -> Tuple[str, Completion]:
    pass


class CacheWorker:
    def __init__(self, pool: Executor) -> None:
        self._db = Database(pool)
        self._cache_ctx = _CacheCtx(buf_id=-1, row=-1, line_before="", comps={})

    def _use_cache(self, context: Context) -> Optional[Sequence[Completion]]:
        match = context.words or context.syms
        words = self._db.select(match)

        def cont() -> Iterator[Completion]:
            for word in words:
                cmp = self._cache_ctx.comps.get(word)
                if cmp:
                    yield cmp

        return tuple(cont())

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

