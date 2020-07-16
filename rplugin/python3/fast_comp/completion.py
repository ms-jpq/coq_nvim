from asyncio import gather, wait_for
from dataclasses import dataclass
from locale import strxfrm
from traceback import format_exc
from typing import AsyncIterator, Iterator, List, Sequence, Tuple, cast

from pynvim import Nvim

from .da import anext
from .nvim import VimCompletion, print
from .types import Factory, SourceCompletion, SourceFactory


@dataclass(frozen=True)
class Step:
    source: str
    priority: float
    comp: SourceCompletion


async def manufacture(
    nvim: Nvim, factory: SourceFactory
) -> AsyncIterator[Sequence[Step]]:
    fact = cast(Factory, factory.manufacture)
    sources = fact(nvim, factory.seed)

    async def source() -> Sequence[Step]:
        results: List[Step] = []

        async def cont() -> None:
            src = await anext(sources)
            async for comp in src:
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
        yield await source()


async def osha(nvim: Nvim, factory: SourceFactory) -> AsyncIterator[Sequence[Step]]:
    fact = manufacture(nvim, factory=factory)
    try:
        async for step in fact:
            yield step
    except Exception as e:
        stack = format_exc()
        await print(nvim, f"{stack}{e}")

    while True:
        yield ()


def rank(annotated: Step) -> Tuple[float, str, str]:
    text = annotated.comp.display or annotated.comp.text
    return annotated.priority, strxfrm(text), strxfrm(annotated.source)


def vimify(annotated: Step) -> VimCompletion:
    comp = annotated.comp
    ret = VimCompletion(word=comp.text, abbr=comp.display, menu=annotated.source)
    return ret


async def merge(
    nvim: Nvim, factories: Iterator[SourceFactory],
) -> AsyncIterator[Sequence[VimCompletion]]:
    sources = tuple(osha(nvim, factory=factory) for factory in factories)

    while True:
        comps = await gather(*(anext(source) for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        yield tuple(map(vimify, completions))
