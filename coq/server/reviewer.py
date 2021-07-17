from collections import Counter
from dataclasses import dataclass, replace
from difflib import SequenceMatcher
from math import inf
from typing import Mapping, MutableSequence, Optional
from uuid import UUID, uuid4

from ..databases.insertions.database import IDB
from ..shared.context import EMPTY_CONTEXT
from ..shared.parse import coalesce, display_width, is_word
from ..shared.runtime import Metric, PReviewer, Worker
from ..shared.settings import BaseClient, Options, Weights
from ..shared.types import Completion, Context


@dataclass(frozen=True)
class _ReviewCtx:
    batch_id: UUID
    context: Context
    neighbours: Mapping[str, int]
    inserted: Mapping[str, int]


@dataclass(frozen=True)
class _MatchMetrics:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int


def _isjunk(s: str) -> bool:
    return s.isspace()


def count(cword: str, match: str) -> _MatchMetrics:
    m = SequenceMatcher(a=cword, b=match, autojunk=True, isjunk=_isjunk)
    matches: MutableSequence[int] = []
    prefix_matches = 0
    num_matches = 0
    consecutive_matches = 0

    for ai, bi, size in m.get_matching_blocks():
        num_matches += size
        if ai == bi == 0:
            prefix_matches = size
        for i in range(bi, bi + size):
            matches.append(i)

    pm_idx = inf
    for i in matches:
        if pm_idx == i - 1:
            consecutive_matches += 1
        pm_idx = i

    metric = _MatchMetrics(
        prefix_matches=prefix_matches,
        consecutive_matches=consecutive_matches,
        num_matches=num_matches,
    )

    return metric


def _metric(
    options: Options,
    context: Context,
    completion: Completion,
) -> _MatchMetrics:
    cword = (
        context.words_before
        if is_word(completion.sort_by[:1], unifying_chars=options.unifying_chars)
        else context.syms_before
    )
    return count(cword, match=completion.sort_by)


def _join(
    batch: UUID,
    ctx: _ReviewCtx,
    completion: Completion,
    match_metrics: _MatchMetrics,
) -> Metric:
    weight = Weights(
        consecutive_matches=match_metrics.consecutive_matches,
        insertion_order=ctx.inserted.get(completion.sort_by, 0),
        neighbours=ctx.neighbours.get(completion.sort_by, 0),
        num_matches=match_metrics.num_matches,
        prefix_matches=match_metrics.prefix_matches,
    )
    label_width = display_width(completion.label, tabsize=ctx.context.tabstop)
    kind_width = display_width(completion.kind, tabsize=ctx.context.tabstop)
    metric = Metric(
        batch=batch,
        comp=completion,
        weight=weight,
        label_width=label_width,
        kind_width=kind_width,
    )
    return metric


class Reviewer(PReviewer):
    def __init__(self, options: Options, db: IDB) -> None:
        self._options, self._db = options, db
        self._ctx = _ReviewCtx(
            batch_id=uuid4(), context=EMPTY_CONTEXT, neighbours={}, inserted={}
        )

    def register(self, worker: Worker, assoc: BaseClient) -> None:
        self._db.new_source(assoc.short_name)

    async def begin(self, context: Context) -> None:
        inserted = await self._db.insertion_order(n_rows=100)
        neighbours = Counter(
            word
            for line in context.lines
            for word in coalesce(line, unifying_chars=self._options.unifying_chars)
        )
        ctx = _ReviewCtx(
            batch_id=uuid4(), context=context, neighbours=neighbours, inserted=inserted
        )
        self._ctx = ctx

    async def s1(self, worker: Worker, assoc: BaseClient, batch: UUID) -> None:
        self._ctx = replace(self._ctx, batch_id=batch)
        await self._db.new_batch(assoc.short_name, batch_id=batch.bytes)

    def s2(self, batch: UUID, completion: Completion) -> Metric:
        match_metrics = _metric(
            self._options,
            context=self._ctx.context,
            completion=completion,
        )
        metric = _join(
            batch, ctx=self._ctx, completion=completion, match_metrics=match_metrics
        )
        return metric

    async def end(self, elapsed: Optional[float], items: Optional[int]) -> None:
        await self._db.update_batch(
            self._ctx.batch_id.bytes, duration=elapsed, items=items
        )

