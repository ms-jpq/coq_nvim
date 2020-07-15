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

from .da import anext
from .types import Factory, SourceCompletion, SourceFactory, VimCompletion


@dataclass(frozen=True)
class Step:
    source: str
    priority: float
    comp: SourceCompletion


async def manufacture(
    nvim: Nvim, factory: SourceFactory
) -> AsyncIterator[Sequence[VimCompletion]]:

    fact = cast(Factory, factory.manufacture)
    sources = await fact(nvim, factory.seed)

    async def source() -> Sequence[Step]:
        src = await anext(sources)
        results: List[Step] = []

        async def cont() -> None:
            async for comp in src():
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

    while True:
        yield source()


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
        comps = await gather(*(source() for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        yield tuple(map(vimify, completions))
