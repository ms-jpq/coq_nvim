from asyncio import gather, wait
from collections import deque
from typing import Awaitable, Callable, Dict, List, Sequence, Set, Tuple

from ..shared.parse import count_matches, parse_common_affix
from ..shared.types import Completion, Context
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
        source=options.source_name,
        source_shortname=options.short_name,
        rank=step.rank,
        text=step.text,
        text_normalized=step.text_normalized,
        comp=comp,
    )
    return new_step


def make_cache(
    match_opt: MatchOptions, cache_opt: CacheOptions,
) -> Tuple[
    Callable[[Context, Sequence[Step]], None],
    Callable[[Context, float], Awaitable[Sequence[Step]]],
]:
    half_band_size = cache_opt.band_size // 2
    queue: deque = deque([])

    # buf -> row -> col
    bufs: Dict[str, Dict[int, Dict[int, Sequence[Step]]]] = {}
    # buf -> row -> col

    def push(context: Context, steps: Sequence[Step]) -> None:
        position = context.position
        queue.append((context.filename, position))

        if len(queue) > cache_opt.band_size:
            bufname, pos = queue.popleft()
            bufs.get(bufname, {}).get(pos.row, {}).pop(pos.col, None)

        rows = bufs.setdefault(context.filename, {})
        cols = rows.setdefault(position.row, {})
        cols[position.col] = steps

    async def pull(context: Context, timeout: float) -> Sequence[Step]:
        position = context.position
        rows = bufs.get(context.filename, {})
        cols = rows.get(position.row, {})
        col = position.col
        cword, ncword = context.alnums, context.alnums_normalized

        acc: List[Step] = []

        async def cont() -> None:
            seen: Set[str] = set()

            for c in range(col - half_band_size, col + half_band_size + 1):
                for step in cols.get(c, ()):
                    text = step.text
                    nword = step.text_normalized
                    if text not in seen:
                        matches = count_matches(cword, word=text, nword=nword)
                        if matches >= match_opt.min_match and nword not in ncword:
                            seen.add(text)
                            new_step = recalculate(
                                context, options=cache_opt, step=step
                            )
                            acc.append(new_step)

        done, pending = await wait((cont(),), timeout=timeout)
        for p in pending:
            p.cancel()
        await gather(*done)

        return acc

    return push, pull
