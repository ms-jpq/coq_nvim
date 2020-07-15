from typing import AsyncIterator

from ..types import Source, SourceCompletion, SourceFeed


def main() -> Source:
    async def source(seed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="")

    return source
