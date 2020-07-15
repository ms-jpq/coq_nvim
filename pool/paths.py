from dataclasses import dataclass
from typing import Any, AsyncIterator, Optional

from pynvim import Nvim


@dataclass(frozen=True)
class SourceSeed:
    config: Optional[Any] = None


@dataclass(frozen=True)
class SourceCompletion:
    text: str
    display: Optional[str] = None
    preview: Optional[str] = None


async def main(
    nvim: Nvim, seed: SourceSeed
) -> AsyncIterator[AsyncIterator[SourceCompletion]]:
    async def source() -> AsyncIterator[SourceCompletion]:
        yield SourceCompletion(text="lsp_stub")

    while True:
        yield source()
