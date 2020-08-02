from asyncio import gather
from os import linesep
from traceback import format_exc
from typing import Optional, Tuple

from pynvim import Nvim

from ..shared.nvim import print
from ..shared.types import SnippetContext, SnippetEngine
from .settings import load_engines
from .types import EngineFactory, Settings


async def osha(
    nvim: Nvim, kind: str, factory: EngineFactory
) -> Tuple[str, Optional[SnippetEngine]]:
    manufacture = factory.manufacture

    try:
        engine = await manufacture(nvim, factory.seed)
    except Exception as e:
        stack = format_exc()
        message = f"Error in snippet engine {kind}{linesep}{stack}{e}"
        await print(nvim, message, error=True)
        return kind, None
    else:
        return kind, engine


async def gen_engine(nvim: Nvim, settings: Settings) -> SnippetEngine:

    factories = load_engines(settings)
    engine_src = await gather(
        *(osha(nvim, kind=kind, factory=factory) for kind, factory in factories.items())
    )
    engines = {kind: engine for kind, engine in engine_src}

    async def engine(context: SnippetContext) -> None:
        kind = context.snippet.kind
        engine = engines.get(kind)
        if engine:
            await engine(context)
        else:
            message = f"No snippet engine found for - {kind}"
            await print(nvim, message, error=True)

    return engine
