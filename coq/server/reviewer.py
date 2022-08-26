from collections import Counter
from dataclasses import dataclass
from itertools import chain
from typing import Mapping
from uuid import UUID, uuid4

from pynvim_pp.lib import display_width

from ..databases.insertions.database import IDB
from ..shared.context import cword_before
from ..shared.fuzzy import MatchMetrics, metrics
from ..shared.parse import coalesce, lower
from ..shared.runtime import Metric, PReviewer
from ..shared.settings import BaseClient, Icons, MatchOptions, Weights
from ..shared.types import Completion, Context
from .icons import iconify


@dataclass(frozen=True)
class ReviewCtx:
    batch: UUID
    context: Context
    proximity: Mapping[str, int]
    inserted: Mapping[str, int]

    is_lower: bool


def _metric(
    options: MatchOptions,
    ctx: ReviewCtx,
    completion: Completion,
) -> MatchMetrics:
    match = lower(completion.sort_by) if ctx.is_lower else completion.sort_by
    cword = cword_before(
        options.unifying_chars, lower=ctx.is_lower, context=ctx.context, sort_by=match
    )
    return metrics(cword, match, look_ahead=options.look_ahead)


def sigmoid(x: float) -> float:
    """
    x -> y ∈ (0.5, 1.5)
    """

    return x / (1 + abs(x)) / 2 + 1


def _join(
    ctx: ReviewCtx,
    instance: UUID,
    completion: Completion,
    match_metrics: MatchMetrics,
) -> Metric:
    weight = Weights(
        prefix_matches=match_metrics.prefix_matches,
        edit_distance=match_metrics.edit_distance,
        recency=ctx.inserted.get(completion.sort_by, 0),
        proximity=ctx.proximity.get(completion.sort_by, 0),
    )
    label_width = display_width(completion.label, tabsize=ctx.context.tabstop)
    # !! WARN
    # Use UTF8 len for icon support
    # !! WARN
    kind_width = len(completion.kind)
    metric = Metric(
        instance=instance,
        comp=completion,
        weight_adjust=sigmoid(completion.weight_adjust),
        weight=weight,
        label_width=label_width,
        kind_width=kind_width,
    )
    return metric


class Reviewer(PReviewer[ReviewCtx]):
    def __init__(self, options: MatchOptions, icons: Icons, db: IDB) -> None:
        self._options, self._icons, self._db = options, icons, db

    def register(self, assoc: BaseClient) -> None:
        self._db.new_source(assoc.short_name)

    async def begin(self, context: Context) -> ReviewCtx:
        inserted = await self._db.insertion_order(n_rows=100)
        words = chain.from_iterable(
            coalesce(
                line,
                unifying_chars=self._options.unifying_chars,
                include_syms=True,
            )
            for line in context.lines
        )
        proximity = Counter(words)

        ctx = ReviewCtx(
            batch=uuid4(),
            context=context,
            proximity=proximity,
            inserted=inserted,
            is_lower=context.is_lower,
        )
        await self._db.new_batch(ctx.batch.bytes)
        return ctx

    async def s_begin(
        self, token: ReviewCtx, assoc: BaseClient, instance: UUID
    ) -> None:
        await self._db.new_instance(
            instance.bytes, source=assoc.short_name, batch_id=token.batch.bytes
        )

    def trans(self, token: ReviewCtx, instance: UUID, completion: Completion) -> Metric:
        new_completion = iconify(self._icons, completion=completion)
        match_metrics = _metric(
            self._options,
            ctx=token,
            completion=new_completion,
        )
        metric = _join(
            token,
            instance=instance,
            completion=new_completion,
            match_metrics=match_metrics,
        )
        return metric

    async def s_end(
        self, instance: UUID, interrupted: bool, elapsed: float, items: int
    ) -> None:
        await self._db.new_stat(
            instance.bytes, interrupted=interrupted, duration=elapsed, items=items
        )
