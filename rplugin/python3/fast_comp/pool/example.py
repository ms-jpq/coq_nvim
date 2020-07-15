from itertools import count
from typing import AsyncIterator

from ..types import Source, SourceCompletion, SourceFeed


def main() -> AsyncIterator[Source]:
    it = count()

    async def source(seed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        num = next(it)
        yield SourceCompletion(text=str(num))

    while True:
        yield source
