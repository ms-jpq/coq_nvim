from typing import AsyncIterator

from ..types import Source, SourceCompletion, SourceFeed


def main() -> AsyncIterator[Source]:
    async def source(seed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="")

    while True:
        yield source
