from asyncio import Queue, gather, wait
from dataclasses import dataclass
from locale import strxfrm
from traceback import format_exc
from typing import (
    Awaitable,
    Callable,
    Dict,
    Iterator,
    List,
    Optional,
    Sequence,
    Tuple,
    cast,
)

from pynvim import Nvim

from .nvim import VimCompletion, call, print
from .types import (
    Factory,
    Notification,
    Position,
    SourceCompletion,
    SourceFactory,
    SourceFeed,
)


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


async def manufacture(nvim: Nvim, factory: SourceFactory) -> Tuple[StepFunction, Queue]:
    chan: Queue = Queue()
    fact = cast(Factory, factory.manufacture)
    src = await fact(nvim, chan, factory.seed)

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

        done, pending = await wait((cont(),), timeout=factory.timeout)
        await gather(*done)
        for p in pending:
            p.cancel()
        return acc

    return source, chan


async def osha(
    nvim: Nvim, factory: SourceFactory
) -> Tuple[str, StepFunction, Optional[Queue]]:
    async def nil_steps(_: SourceFeed) -> Sequence[Step]:
        return ()

    try:
        step_fn, chan = await manufacture(nvim, factory=factory)
    except Exception as e:
        stack = format_exc()
        message = f"Error in source {factory.name}\n{stack}{e}"
        await print(nvim, message, error=True)
        return factory.name, nil_steps, None
    else:

        async def o_step(feed: SourceFeed) -> Sequence[Step]:
            try:
                return await step_fn(feed)
            except Exception as e:
                stack = format_exc()
                message = f"Error in source {factory.name}\n{stack}{e}"
                await print(nvim, message, error=True)
                return ()

        return factory.name, o_step, chan


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
    nvim: Nvim, chan: Queue, factories: Iterator[SourceFactory],
) -> Tuple[
    Callable[[], Awaitable[Iterator[VimCompletion]]], Callable[[], Awaitable[None]]
]:
    src_gen = await gather(*(osha(nvim, factory=factory) for factory in factories))
    chans: Dict[str, Queue] = {name: chan for name, _, chan in src_gen}
    sources = tuple(source for _, source, _ in src_gen)

    async def gen() -> Iterator[VimCompletion]:
        feed = await gen_feed(nvim)
        comps = await gather(*(source(feed) for source in sources))
        completions = sorted((c for co in comps for c in co), key=rank)
        return map(vimify, completions)

    async def listen() -> None:
        while True:
            notif: Notification = await chan.get()
            source = notif.source
            ch = chans.get(source)
            if ch:
                await ch.put(notif.body)
            else:
                await print(
                    nvim, f"Notification to uknown source - {source}", error=True
                )

    return gen, listen
