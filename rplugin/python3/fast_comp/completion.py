from asyncio import gather, wait_for
from dataclasses import dataclass
from locale import strxfrm
from math import inf
from typing import AsyncIterator, Iterable, List, Sequence, Tuple

from pynvim import Nvim

from .nvim import call
from .types import (
    Source,
    SourceCompletion,
    SourceFactory,
    SourceFeed,
    SourceSeed,
    VimCompletion,
)


@dataclass(frozen=True)
class Step:
    source: str
    priority: int
    comp: SourceCompletion


async def gen_feed(nvim: Nvim) -> SourceFeed:
    def cont() -> SourceFeed:
        cwd = nvim.funcs.getcwd()
        cword = ""
        return SourceFeed(cwd=cwd, cword=cword)

    return await call(nvim, cont)


async def step(source: Source, feed: SourceFeed) -> Sequence[Step]:
    timeout = source.timeout or inf
    results: List[Step] = []

    async def cont() -> None:
        async for comp in source.step(feed):
            completion = Step(source=source.name, priority=source.priority, comp=comp)
            results.append(completion)

    try:
        await wait_for(cont(), timeout)
    except TimeoutError:
        return results
    else:
        return results


def rank(annotated: Step) -> Tuple[int, str, str]:
    text = annotated.comp.display or annotated.comp.text
    return annotated.priority, strxfrm(text), strxfrm(annotated.source)


def vimify(annotated: Step) -> VimCompletion:
    comp = annotated.comp
    ret = VimCompletion(word=comp.text, abbr=comp.display, menu=annotated.source)
    return ret


async def merge(
    nvim: Nvim, factories: Iterable[SourceFactory]
) -> AsyncIterator[Sequence[VimCompletion]]:
    seed = SourceSeed(priority=1)
    sources = tuple(fact(nvim, seed) for fact in factories)

    while True:
        feed = await gen_feed(nvim)
        comps = await gather(*(step(source, feed=feed) for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        yield tuple(map(vimify, completions))
