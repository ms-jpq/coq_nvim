from asyncio import Queue, gather, wait
from dataclasses import dataclass
from itertools import chain
from math import inf
from os import linesep
from traceback import format_exc
from typing import Awaitable, Callable, Dict, Iterator, List, Optional, Sequence, Tuple

from pynvim import Nvim

from ..shared.nvim import print
from ..shared.parse import normalize
from ..shared.types import Context, Position
from .cache import make_cache
from .context import gen_context
from .fuzzy import fuzzer
from .nvim import VimCompletion
from .settings import load_factories
from .types import Notification, Settings, SourceFactory, Step


@dataclass(frozen=True)
class GenOptions:
    force: bool = False


@dataclass(frozen=True)
class StepContext:
    force: bool


StepFunction = Callable[[Context, StepContext], Awaitable[Sequence[Step]]]


async def manufacture(
    nvim: Nvim, name: str, factory: SourceFactory
) -> Tuple[StepFunction, Queue]:
    chan: Queue = Queue()
    src = await factory.manufacture(nvim, chan, factory.seed)

    async def source(context: Context, s_context: StepContext) -> Sequence[Step]:
        timeout = inf if s_context.force else factory.timeout
        acc: List[Step] = []

        async def cont() -> None:
            async for comp in src(context):
                text = (
                    comp.snippet.match
                    if comp.snippet
                    else comp.new_prefix + comp.new_suffix
                )
                normalized_text = normalize(text)
                step = Step(
                    source=name,
                    source_shortname=factory.short_name,
                    rank=factory.rank,
                    text=text,
                    text_normalized=normalized_text,
                    comp=comp,
                )
                acc.append(step)

        done, pending = await wait((cont(),), timeout=timeout)
        for p in pending:
            p.cancel()
        await gather(*done)
        if pending:
            timeout_fmt = round(timeout * 1000)
            msg1 = "⚠️  Completion source timed out - "
            msg2 = f"{name}, exceeded {timeout_fmt}ms{linesep}"
            await print(nvim, msg1 + msg2)
        return acc

    return source, chan


async def osha(
    nvim: Nvim, name: str, factory: SourceFactory
) -> Tuple[str, StepFunction, Optional[Queue]]:
    async def nil_steps(_: Context, __: StepContext) -> Sequence[Step]:
        return ()

    try:
        step_fn, chan = await manufacture(nvim, name=name, factory=factory)
    except Exception as e:
        stack = format_exc()
        message = f"Error in source {name}{linesep}{stack}{e}"
        await print(nvim, message, error=True)
        return name, nil_steps, None
    else:
        errored = False

        async def o_step(context: Context, s_context: StepContext) -> Sequence[Step]:
            nonlocal errored
            try:
                if errored:
                    return ()
                else:
                    return await step_fn(context, s_context)
            except Exception as e:
                errored = True
                stack = format_exc()
                message = f"Error in source {name}{linesep}{stack}{e}"
                await print(nvim, message, error=True)
                return ()

        return name, o_step, chan


async def merge(
    nvim: Nvim, chan: Queue, settings: Settings
) -> Tuple[
    Callable[[GenOptions], Awaitable[Tuple[Position, Iterator[VimCompletion]]]],
    Callable[[], Awaitable[None]],
]:
    match_opt = settings.match
    cache_opt = settings.cache
    unifying_chars = match_opt.unifying_chars

    factories = load_factories(settings=settings)
    limits = {
        **{name: fact.limit for name, fact in factories.items()},
        cache_opt.source_name: cache_opt.limit,
    }
    fuzzy = fuzzer(match_opt, limits=limits)
    push, pull = make_cache(match_opt=match_opt, cache_opt=cache_opt)

    src_gen = await gather(
        *(osha(nvim, name=name, factory=factory) for name, factory in factories.items())
    )
    chans: Dict[str, Optional[Queue]] = {name: chan for name, _, chan in src_gen}
    sources: Dict[str, StepFunction] = {name: source for name, source, _ in src_gen}

    async def gen(options: GenOptions) -> Tuple[Position, Iterator[VimCompletion]]:
        context = await gen_context(nvim, unifying_chars=unifying_chars)
        s_context = StepContext(force=options.force)
        position = context.position
        go = context.line_before and not context.line_before.isspace()
        if go or options.force:
            source_gen = (
                source(context, s_context) for name, source in sources.items()
            )

            max_wait = min(*(fact.timeout for fact in factories.values()), 0)
            cached, *comps = await gather(pull(context, max_wait), *source_gen)
            steps = tuple(c for co in comps for c in co)
            push(context, steps)
            all_steps = chain(steps, cached)

            return position, fuzzy(context, all_steps)
        else:
            return position, iter(())

    async def listen() -> None:
        while True:
            notif: Notification = await chan.get()
            source = notif.source
            ch = chans.get(source)
            if ch:
                await ch.put(notif.body)
            elif source in chans:
                await print(
                    nvim, f"Notification to uknown source - {source}", error=True
                )

    return gen, listen
