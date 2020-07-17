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
        acc: List[Step] = []

        async def cont() -> None:
            src = await anext(sources)
            async for comp in src:
                completion = Step(
                    source=factory.short_name, priority=factory.priority, comp=comp
                )
                acc.append(completion)
                if len(acc) >= factory.limit:
                    break

        try:
            await wait_for(cont(), factory.timeout)
        except TimeoutError:
            return acc
        else:
            return acc

    while True:
        yield await source()


async def osha(nvim: Nvim, factory: SourceFactory) -> AsyncIterator[Sequence[Step]]:
    fact = manufacture(nvim, factory=factory)
    try:
        async for step in fact:
            yield step
    except Exception as e:
        stack = format_exc()
        await print(nvim, f"{stack}{e}", error=True)

    while True:
        yield ()


def rank(annotated: Step) -> Tuple[float, float, str, str]:
    comp = annotated.comp
    text = comp.display or comp.text
    priority = comp.priority or 0
    return annotated.priority, priority, strxfrm(text), strxfrm(annotated.source)


def vimify(annotated: Step) -> VimCompletion:
    comp = annotated.comp
    short_name = f"[{annotated.source}]"
    ret = VimCompletion(
        equal=1, word=comp.text, abbr=comp.display, menu=short_name, info=comp.detail
    )
    return ret


async def merge(
    nvim: Nvim, factories: Iterator[SourceFactory],
) -> AsyncIterator[Sequence[VimCompletion]]:
    sources = tuple(osha(nvim, factory=factory) for factory in factories)

    while True:
        comps = await gather(*(anext(source) for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        yield tuple(map(vimify, completions))
