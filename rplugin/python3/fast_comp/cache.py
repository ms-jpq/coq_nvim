from collections import deque
from itertools import chain
from typing import Awaitable, Callable, Dict, Iterator, Sequence, Set, Tuple

from .types import FuzzyOptions, SourceCompletion, SourceFeed, Step


def shift_step(feed: SourceFeed, step: Step) -> Step:
    comp = step.comp
    old_prefix, old_suffix = comp.old_prefix, comp.old_suffix
    old_col, new_col = comp.position.col, feed.position.col

    col_diff = new_col - old_col
    n_o_prefix = " " * (len(old_prefix) + col_diff)
    n_o_suffix = " " * (len(old_suffix) - col_diff)

    new_comp = SourceCompletion(
        position=comp.position,
        old_prefix=n_o_prefix,
        new_prefix=comp.new_prefix,
        old_suffix=n_o_suffix,
        new_suffix=comp.new_prefix,
        label=comp.label,
        sortby=comp.sortby,
        kind=comp.kind,
        doc=comp.doc,
    )
    return Step(
        source=step.source,
        source_shortname=step.source_shortname,
        priority=step.priority,
        normalized=step.normalized,
        comp=new_comp,
    )


def make_cache(
    options: FuzzyOptions,
) -> Tuple[
    Callable[[SourceFeed, Sequence[Step]], None],
    Callable[[SourceFeed], Awaitable[Sequence[Step]]],
]:
    half_band_size = options.band_size // 2
    queue: deque = deque([])

    # buf -> row -> col
    bufs: Dict[str, Dict[int, Dict[int, Sequence[Step]]]] = {}
    # buf -> row -> col

    def push(feed: SourceFeed, steps: Sequence[Step]) -> None:
        position = feed.position
        queue.append((feed.filename, position))

        if len(queue) > options.band_size:
            bufname, pos = queue.popleft()
            bufs.get(bufname, {}).get(pos.row, {}).pop(pos.col, None)

        rows = bufs.setdefault(feed.filename, {})
        cols = rows.setdefault(position.row, {})
        cols[position.col] = steps

    async def retrieve(feed: SourceFeed) -> Sequence[Step]:
        position = feed.position
        rows = bufs.get(feed.filename, {})
        cols = rows.get(position.row, {})
        col = position.col

        def cont() -> Iterator[Step]:
            seen: Set[Step] = set()
            for c in chain(
                range(col - half_band_size, col),
                range(col + 1, col + half_band_size + 1),
            ):
                for step in cols.get(c, ()):
                    if step not in seen:
                        seen.add(step)
                        yield shift_step(feed, step=step)

        return tuple(cont())

    return push, retrieve
