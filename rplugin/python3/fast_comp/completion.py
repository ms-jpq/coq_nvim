from asyncio import Queue, gather, wait
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

from .fuzzy import fuzzer
from .nvim import VimCompletion, call, print
from .types import Factory, Notification, Position, SourceFactory, SourceFeed, Step

StepFunction = Callable[[SourceFeed], Awaitable[Sequence[Step]]]


def parse_prefix(line: str, col: int) -> Tuple[bool, str]:
    before = line[:col]
    acc: List[str] = []
    a = ""
    for c in reversed(before):
        if not a:
            a = c
        if c.isalnum():
            acc.append(c)
        else:
            break

    go = a != "" and not a.isspace()
    prefix = "".join(reversed(acc))
    return go, prefix


async def gen_feed(nvim: Nvim) -> Tuple[bool, SourceFeed]:
    def fed() -> Tuple[bool, SourceFeed]:
        buffer = nvim.api.get_current_buf()
        filetype = nvim.api.buf_get_option(buffer, "filetype")
        window = nvim.api.get_current_win()
        row, col = nvim.api.win_get_cursor(window)
        line = nvim.api.get_current_line()
        position = Position(row=row, col=col)
        go, prefix = parse_prefix(line, col)
        return (
            go,
            SourceFeed(filetype=filetype, position=position, line=line, prefix=prefix),
        )

    return await call(nvim, fed)


async def manufacture(nvim: Nvim, factory: SourceFactory) -> Tuple[StepFunction, Queue]:
    chan: Queue = Queue()
    fact = cast(Factory, factory.manufacture)
    src = await fact(nvim, chan, factory.seed)

    async def source(feed: SourceFeed) -> Sequence[Step]:
        acc: List[Step] = []

        async def cont() -> None:
            async for comp in src(feed):
                normalized = comp.text.lower()
                completion = Step(
                    source=factory.short_name,
                    priority=factory.priority,
                    normalized=normalized,
                    comp=comp,
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


async def merge(
    nvim: Nvim, chan: Queue, factories: Iterator[SourceFactory],
) -> Tuple[
    Callable[[], Awaitable[Tuple[Position, Iterator[VimCompletion]]]],
    Callable[[], Awaitable[None]],
]:
    fuzzy = fuzzer()
    src_gen = await gather(*(osha(nvim, factory=factory) for factory in factories))
    chans: Dict[str, Queue] = {name: chan for name, _, chan in src_gen}
    sources = tuple(source for _, source, _ in src_gen)

    async def gen() -> Tuple[Position, Iterator[VimCompletion]]:
        go, feed = await gen_feed(nvim)
        position = feed.position
        if go:
            comps = await gather(*(source(feed) for source in sources))
            completions = (c for co in comps for c in co)
            return position, fuzzy(feed, completions)
        else:
            return position, iter(())

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
