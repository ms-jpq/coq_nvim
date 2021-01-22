from asyncio import Queue, gather
from os import linesep
from typing import Callable, Dict, Optional, Tuple

from pynvim import Nvim

from ..shared.types import Comm, SnippetContext, SnippetEngine
from .settings import load_engines
from .types import EngineFactory, Settings, Snippet


async def osha(
    nvim: Nvim, kind: str, factory: EngineFactory
) -> Tuple[str, Queue, Optional[SnippetEngine]]:
    manufacture = factory.manufacture
    chan: Queue = Queue()
    comm = Comm(nvim=nvim, chan=chan)

    try:
        engine = await manufacture(comm, factory.seed)
    except Exception as e:
        message = f"Error in snippet engine {kind}{linesep}{e}"
        log.exception("%s", message)
        return kind, chan, None
    else:
        return kind, chan, engine


async def gen_engine(
    nvim: Nvim, settings: Settings
) -> Tuple[SnippetEngine, Dict[str, Queue], Callable[[Snippet], bool]]:

    factories = load_engines(settings)
    engine_src = await gather(
        *(osha(nvim, kind=kind, factory=factory) for kind, factory in factories.items())
    )
    engines = {kind: engine for kind, _, engine in engine_src if engine}
    chans = {kind: chan for kind, chan, engine in engine_src if engine}

    async def engine(context: SnippetContext) -> None:
        kind = context.snippet.kind
        engine = engines.get(kind)
        if engine:
            await engine(context)
        else:
            message = f"No snippet engine found for - {kind}"
            log.error("%s", message)

    def available(snippet: Snippet) -> bool:
        return snippet.kind in engines

    return engine, chans, available
