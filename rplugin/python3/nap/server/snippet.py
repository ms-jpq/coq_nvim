from pynvim import Nvim

from ..shared.types import SnippetContext, SnippetEngine
from .settings import load_engines
from .types import Settings


async def gen_engine(nvim: Nvim, settings: Settings) -> SnippetEngine:
    async def engine(context: SnippetContext) -> None:
        pass

    return engine
