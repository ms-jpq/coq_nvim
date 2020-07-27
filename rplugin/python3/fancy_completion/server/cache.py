from asyncio import gather, wait
from collections import deque
from typing import Awaitable, Callable, Dict, List, Sequence, Set, Tuple

from ..shared.parse import parse_common_affix
from ..shared.types import Completion, Context
from .types import CacheOptions, Step


def recalculate(context: Context, options: CacheOptions, step: Step) -> Step:
    old_prefix, old_suffix = parse_common_affix(
        context, match_normalized=step.text_normalized
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
        text=step.text,
        text_normalized=step.text_normalized,
        comp=comp,
    )
    return new_step


def make_cache(
    options: CacheOptions,
) -> Tuple[
    Callable[[Context, Sequence[Step]], None],
    Callable[[Context, float], Awaitable[Sequence[Step]]],
]:
    half_band_size = options.band_size // 2
    queue: deque = deque([])

    # buf -> row -> col
    bufs: Dict[str, Dict[int, Dict[int, Sequence[Step]]]] = {}
    # buf -> row -> col

    def push(context: Context, steps: Sequence[Step]) -> None:
        position = context.position
        queue.append((context.filename, position))

        if len(queue) > options.band_size:
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

        acc: List[Step] = []

        async def cont() -> None:
            seen: Set[str] = set()

            for c in range(col - half_band_size, col + half_band_size + 1):
                for step in cols.get(c, ()):
                    text = step.text
                    if text not in seen:
                        seen.add(text)
                        new_step = recalculate(context, options=options, step=step)
                        acc.append(new_step)

        done, pending = await wait((cont(),), timeout=timeout)
        for p in pending:
            p.cancel()
        await gather(*done)

        return acc

    return push, pull
