from typing import Iterator

from pynvim import Nvim

from ..shared.types import SnippetContext, SnippetEngine
from .types import EngineFactory


async def gen_engine(
    nvim: Nvim, factories: Iterator[EngineFactory]
) -> SnippetEngine:
    async def engine(context: SnippetContext) -> None:
        pass

    return engine
