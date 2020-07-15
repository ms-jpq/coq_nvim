from asyncio import gather, wait_for
from dataclasses import dataclass
from locale import strxfrm
from typing import (
    AsyncIterator,
    Awaitable,
    Callable,
    Iterable,
    List,
    Sequence,
    Tuple,
    cast,
)

from pynvim import Nvim

from .nvim import call
from .types import Factory, SourceCompletion, SourceFactory, SourceFeed, VimCompletion


@dataclass(frozen=True)
class Step:
    source: str
    priority: float
    comp: SourceCompletion


async def gen_feed(nvim: Nvim) -> SourceFeed:
    def cont() -> SourceFeed:
        cwd = nvim.funcs.getcwd()
        cword = ""
        return SourceFeed(cwd=cwd, cword=cword)

    return await call(nvim, cont)


def manufacture(
    nvim: Nvim, factory: SourceFactory
) -> Callable[[SourceFeed], Awaitable[Sequence[Step]]]:

    fact = cast(Factory, factory.manufacture)
    wheel = fact(nvim, factory.seed)

    async def source(feed: SourceFeed) -> Sequence[Step]:
        results: List[Step] = []

        async def cont() -> None:
            async for comp in wheel(feed):
                completion = Step(
                    source=factory.name, priority=factory.priority, comp=comp
                )
                results.append(completion)

        try:
            await wait_for(cont(), factory.timeout)
        except TimeoutError:
            return results
        else:
            return results

    return source


def rank(annotated: Step) -> Tuple[float, str, str]:
    text = annotated.comp.display or annotated.comp.text
    return annotated.priority, strxfrm(text), strxfrm(annotated.source)


def vimify(annotated: Step) -> VimCompletion:
    comp = annotated.comp
    ret = VimCompletion(word=comp.text, abbr=comp.display, menu=annotated.source)
    return ret


async def merge(
    nvim: Nvim, factories: Iterable[SourceFactory],
) -> AsyncIterator[Sequence[VimCompletion]]:
    sources = tuple(manufacture(nvim, factory=factory) for factory in factories)

    while True:
        feed = await gen_feed(nvim)
        comps = await gather(*(source(feed) for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        yield tuple(map(vimify, completions))
