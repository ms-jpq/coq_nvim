from collections import Counter
from dataclasses import dataclass
from itertools import chain
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

    l_words_before: str
    l_syms_before: str
    is_lower: bool


def _metric(
    options: Options,
    ctx: _ReviewCtx,
    completion: Completion,
) -> MatchMetrics:
    lsy = lower(completion.sort_by)
    m_lower = lsy == completion.sort_by
    match = lsy if ctx.is_lower and m_lower else completion.sort_by
    cword = (
        (ctx.l_words_before if m_lower else ctx.context.words_before)
        if is_word(match[:1], unifying_chars=options.unifying_chars)
        else (ctx.l_syms_before if m_lower else ctx.context.syms_before)
    )
    return metrics(cword, match, look_ahead=options.look_ahead)


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
            l_words_before="",
            l_syms_before="",
            is_lower=True,
        )

    def register(self, assoc: BaseClient) -> None:
        self._db.new_source(assoc.short_name)

    async def begin(self, context: Context) -> None:
        inserted = await self._db.insertion_order(n_rows=100)
        words = coalesce(
            chain.from_iterable(context.lines),
            unifying_chars=self._options.unifying_chars,
        )
        neighbours = Counter(words)

        l_words_before = lower(context.words_before)
        ctx = _ReviewCtx(
            batch=uuid4(),
            context=context,
            neighbours=neighbours,
            inserted=inserted,
            is_lower=l_words_before == context.words_before,
            l_words_before=l_words_before,
            l_syms_before=lower(context.syms_before),
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

