from typing import AsyncIterator

from pynvim import Nvim

from ..types import Source, SourceCompletion, SourceSeed


async def main(nvim: Nvim, seed: SourceSeed) -> AsyncIterator[Source]:
    async def source() -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="buffers_stub")

    while True:
        yield source
