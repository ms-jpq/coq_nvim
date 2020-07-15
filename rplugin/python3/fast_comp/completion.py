from asyncio import gather, wait_for
from locale import strxfrm
from math import inf
from typing import AsyncIterator, Iterable, List, Sequence, Tuple

from pynvim import Nvim

from .nvim import call
from .types import Completion, Source, SourceFactory, SourceFeed, SourceSeed


async def gen_feed(nvim: Nvim) -> SourceFeed:
    def cont() -> SourceFeed:
        cwd = nvim.funcs.getcwd()
        cword = ""
        return SourceFeed(cwd=cwd, cword=cword)

    return await call(nvim, cont)


async def step(source: Source, feed: SourceFeed) -> Sequence[Completion]:
    timeout = source.timeout or inf
    results: List[Completion] = []

    async def cont() -> None:
        wheel = source.step
        async for comp in wheel(feed):
            completion = Completion(
                source=source.name,
                priority=source.priority,
                display=comp.display,
                content=comp.content,
            )
            results.append(completion)

    try:
        await wait_for(cont(), timeout)
    except TimeoutError:
        return results
    else:
        return results


def rank(comp: Completion) -> Tuple[int, str, str]:
    return comp.priority, strxfrm(comp.display), strxfrm(comp.source)


async def merge(
    nvim: Nvim, factories: Iterable[SourceFactory]
) -> AsyncIterator[Sequence[Completion]]:
    seed = SourceSeed(priority=1)
    sources = tuple(fact(nvim, seed) for fact in factories)

    while True:
        feed = await gen_feed(nvim)
        comps = await gather(*(step(source, feed=feed) for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        yield completions
