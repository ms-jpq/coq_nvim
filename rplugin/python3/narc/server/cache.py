from asyncio import gather, wait
from collections import deque
from typing import Awaitable, Callable, Dict, List, Sequence, Set, Tuple

from ..shared.match import gen_metric
from ..shared.parse import parse_common_affix
from ..shared.types import Completion, Context
from .fuzzy import FuzzyStep
from .types import CacheOptions, MatchOptions, Step


def recalculate(context: Context, options: CacheOptions, step: Step) -> Step:
    old_prefix = context.alnums_before
    _, old_suffix = parse_common_affix(
        context, match_normalized=step.text_normalized, use_line=False
    )
    comp = Completion(
        position=context.position,
        old_prefix=old_prefix,
        new_prefix=step.comp.new_prefix,
        old_suffix=old_suffix,
        new_suffix=step.comp.new_suffix,
    )
    new_step = Step(
        source=step.source,
        source_shortname=step.source_shortname,
        rank=step.rank,
        text=step.text,
        text_normalized=step.text_normalized,
        comp=comp,
    )
    return new_step


def make_cache(
    match_opt: MatchOptions, cache_opt: CacheOptions,
) -> Tuple[
    Callable[[Context, Sequence[FuzzyStep]], None],
    Callable[[Context, float], Awaitable[Sequence[FuzzyStep]]],
]:
    half_band_size = cache_opt.band_size // 2
    queue: deque = deque([])

    # buf -> row -> col
    bufs: Dict[str, Dict[int, Dict[int, Sequence[Step]]]] = {}
    # buf -> row -> col

    def push(context: Context, steps: Sequence[FuzzyStep]) -> None:
        position = context.position
        queue.append((context.filename, position))

        if len(queue) > cache_opt.band_size:
            bufname, pos = queue.popleft()
            bufs.get(bufname, {}).get(pos.row, {}).pop(pos.col, None)

        rows = bufs.setdefault(context.filename, {})
        cols = rows.setdefault(position.row, {})
        cols[position.col] = tuple(step.step for step in steps)

    async def pull(context: Context, timeout: float) -> Sequence[FuzzyStep]:
        position = context.position
        rows = bufs.get(context.filename, {})
        cols = rows.get(position.row, {})
        col = position.col
        cword, ncword = context.alnums, context.alnums_normalized

        acc: List[FuzzyStep] = []

        async def cont() -> None:
            seen: Set[str] = set()

            for c in range(col - half_band_size, col + half_band_size + 1):
                for step in cols.get(c, ()):
                    text = step.text
                    nword = step.text_normalized
                    if text not in seen and nword not in ncword:
                        seen.add(text)
                        metric = gen_metric(
                            cword,
                            ncword=ncword,
                            match=text,
                            n_match=nword,
                            options=match_opt,
                            use_secondary=True
                        )
                        if metric.num_matches >= cache_opt.min_match:
                            new_step = recalculate(
                                context, options=cache_opt, step=step
                            )
                            fuzzystep = FuzzyStep(step=new_step, metric=metric,)
                            acc.append(fuzzystep)

        done, pending = await wait((cont(),), timeout=timeout)
        for p in pending:
            p.cancel()
        await gather(*done)

        return acc

    return push, pull
