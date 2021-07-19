from collections import Counter
from dataclasses import dataclass
from typing import Mapping
from uuid import UUID, uuid4

from ..databases.insertions.database import IDB
from ..shared.context import EMPTY_CONTEXT
from ..shared.fuzzy import MatchMetrics, metrics
from ..shared.parse import coalesce, display_width, is_word, lower
from ..shared.runtime import Metric, PReviewer
from ..shared.settings import BaseClient, Options, Weights
from ..shared.types import Completion, Context


@dataclass(frozen=True)
class _ReviewCtx:
    batch: UUID
    context: Context
    neighbours: Mapping[str, int]
    inserted: Mapping[str, int]

    is_lower: bool
    w_before: str
    sw_before: str


def _metric(
    options: Options,
    ctx: _ReviewCtx,
    completion: Completion,
) -> MatchMetrics:
    match = lower(completion.sort_by) if ctx.is_lower else completion.sort_by
    cword = (
        ctx.w_before
        if is_word(match[:1], unifying_chars=options.unifying_chars)
        else ctx.sw_before
    )
    return metrics(cword, match=match, look_ahead=options.look_ahead)


def _join(
    instance: UUID,
    ctx: _ReviewCtx,
    completion: Completion,
    match_metrics: MatchMetrics,
) -> Metric:
    weight = Weights(
        prefix_matches=match_metrics.prefix_matches,
        edit_distance=match_metrics.edit_distance,
        insertion_order=ctx.inserted.get(completion.sort_by, 0),
        neighbours=ctx.neighbours.get(completion.sort_by, 0),
    )
    label_width = display_width(completion.label, tabsize=ctx.context.tabstop)
    kind_width = display_width(completion.kind, tabsize=ctx.context.tabstop)
    metric = Metric(
        istance=instance,
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
            batch=uuid4(),
            context=EMPTY_CONTEXT,
            neighbours={},
            inserted={},
            is_lower=True,
            w_before="",
            sw_before="",
        )

    def register(self, assoc: BaseClient) -> None:
        self._db.new_source(assoc.short_name)

    async def begin(self, context: Context) -> None:
        inserted = await self._db.insertion_order(n_rows=100)
        neighbours = Counter(
            word
            for line in context.lines
            for word in coalesce(line, unifying_chars=self._options.unifying_chars)
        )
        ctx = _ReviewCtx(
            batch=uuid4(),
            context=context,
            neighbours=neighbours,
            inserted=inserted,
            is_lower=lower(context.words_before) == context.words_before,
            w_before=context.words_before,
            sw_before=context.syms_before + context.words_before,
        )
        self._ctx = ctx
        await self._db.new_batch(ctx.batch.bytes)

    async def s_begin(self, assoc: BaseClient, instance: UUID) -> None:
        await self._db.new_instance(
            instance.bytes, source=assoc.short_name, batch_id=self._ctx.batch.bytes
        )

    def trans(self, instance: UUID, completion: Completion) -> Metric:
        match_metrics = _metric(
            self._options,
            ctx=self._ctx,
            completion=completion,
        )
        metric = _join(
            instance, ctx=self._ctx, completion=completion, match_metrics=match_metrics
        )
        return metric

    async def s_end(
        self, instance: UUID, interrupted: bool, elapsed: float, items: int
    ) -> None:
        await self._db.new_stat(
            instance.bytes, interrupted=interrupted, duration=elapsed, items=items
        )

