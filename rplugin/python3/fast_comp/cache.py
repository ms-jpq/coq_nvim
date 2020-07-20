from collections import deque
from itertools import chain
from typing import Awaitable, Callable, Dict, Iterator, Sequence, Set, Tuple

from .types import FuzzyOptions, SourceFeed, Step


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
                        yield step

        return tuple(cont())

    return push, retrieve
