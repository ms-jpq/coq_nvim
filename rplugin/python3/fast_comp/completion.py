from asyncio import gather, wait
from dataclasses import dataclass
from locale import strxfrm
from traceback import format_exc
from typing import Awaitable, Callable, Iterator, List, Sequence, Tuple, cast

from pynvim import Nvim

from .da import anext
from .nvim import VimCompletion, call, print
from .types import Factory, Position, SourceCompletion, SourceFactory, SourceFeed


@dataclass(frozen=True)
class Step:
    source: str
    priority: float
    comp: SourceCompletion


StepFunction = Callable[[SourceFeed], Awaitable[Sequence[Step]]]


async def gen_feed(nvim: Nvim) -> SourceFeed:
    def pos() -> Position:
        window = nvim.api.get_current_win()
        row, col = nvim.api.win_get_cursor(window)
        return Position(row=row, col=col)

    position = await call(nvim, pos)
    return SourceFeed(position=position)


async def manufacture(nvim: Nvim, factory: SourceFactory) -> StepFunction:
    fact = cast(Factory, factory.manufacture)
    src = await fact(nvim, factory.seed)

    async def source(feed: SourceFeed) -> Sequence[Step]:
        acc: List[Step] = []

        async def cont() -> None:
            async for comp in src(feed):
                completion = Step(
                    source=factory.short_name, priority=factory.priority, comp=comp
                )
                acc.append(completion)
                if len(acc) >= factory.limit:
                    break

        _, pending = await wait((cont(),), timeout=factory.timeout)
        for p in pending:
            p.cancel()
        return acc

    return source


async def osha(nvim: Nvim, factory: SourceFactory) -> StepFunction:
    async def nil_steps(_: SourceFeed) -> Sequence[Step]:
        return ()

    try:
        step_fn = await manufacture(nvim, factory=factory)
    except Exception as e:
        stack = format_exc()
        await print(nvim, f"{stack}{e}", error=True)
        return nil_steps
    else:

        async def o_step(feed: SourceFeed) -> Sequence[Step]:
            try:
                return await step_fn(feed)
            except Exception as e:
                stack = format_exc()
                await print(nvim, f"{stack}{e}", error=True)
                return ()

        return o_step


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
) -> Callable[[], Awaitable[Iterator[VimCompletion]]]:
    sources = await gather(*(osha(nvim, factory=factory) for factory in factories))

    async def gen() -> Iterator[VimCompletion]:
        feed = await gen_feed(nvim)
        comps = await gather(*(source(feed) for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        return map(vimify, completions)

    return gen
