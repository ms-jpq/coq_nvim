from asyncio import Queue, gather
from os import linesep
from typing import Optional, Tuple

from pynvim import Nvim

from ..shared.types import Comm, SnippetContext, SnippetEngine
from .logging import log
from .settings import load_engines
from .types import EngineFactory, Settings


async def osha(
    nvim: Nvim, kind: str, factory: EngineFactory
) -> Tuple[str, Optional[SnippetEngine]]:
    manufacture = factory.manufacture
    comm = Comm(nvim=nvim, chan=Queue(), log=log)

    try:
        engine = await manufacture(comm, factory.seed)
    except Exception as e:
        message = f"Error in snippet engine {kind}{linesep}{e}"
        log.exception("%s", message)
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
            log.error("%s", message)

    return engine
