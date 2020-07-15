from typing import AsyncIterator

from pynvim import Nvim

from _types import SourceCompletion, SourceSeed


async def main(
    nvim: Nvim, seed: SourceSeed
) -> AsyncIterator[AsyncIterator[SourceCompletion]]:
    async def source() -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="paths_stub")

    while True:
        yield source()
