from concurrent.futures import Executor
from dataclasses import dataclass
from typing import Optional, Sequence

from ...shared.types import Completion, Context
from .database import Database


@dataclass(frozen=True)
class _CacheCtx:
    buf_id: int
    row: int
    line_before: str


class CacheWorker:
    def __init__(self, pool: Executor) -> None:
        self._db = Database(pool)
        self._cache_ctx = _CacheCtx(buf_id=-1, row=-1, line_before="")

    def _use_cache(self, context: Context) -> Optional[Sequence[Completion]]:
        pass

    def _set_cache(self, context: Context, completions: Sequence[Completion]) -> None:
        pass

