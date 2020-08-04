from asyncio import Queue, as_completed, gather, wait
from dataclasses import dataclass
from itertools import chain
from math import inf
from os import linesep
from traceback import format_exc
from typing import (
    AsyncIterator,
    Awaitable,
    Callable,
    Dict,
    Iterator,
    List,
    Optional,
    Sequence,
    Tuple,
)

from pynvim import Nvim

from ..shared.nvim import print
from ..shared.parse import normalize
from ..shared.types import Context, Position
from .cache import make_cache
from .context import gen_context
from .fuzzy import FuzzyStep, fuzzify, fuzzy
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
    match_opt, cache_opt = settings.match, settings.cache
    factories = load_factories(settings=settings)
    src_gen = await gather(
        *(osha(nvim, name=name, factory=factory) for name, factory in factories.items())
    )
    push, pull = make_cache(match_opt=match_opt, cache_opt=cache_opt)

    f_enabled: Dict[str, bool] = {
        name: factory.enabled for name, factory in factories.items()
    }
    sources: Dict[str, StepFunction] = {name: source for name, source, _ in src_gen}

    async def gen(options: GenOptions) -> Tuple[Position, Iterator[VimCompletion]]:
        s_context = StepContext(force=options.force)
        context, buf_context = await gen_context(nvim, options=match_opt, pos=None)
        position = context.position

        def is_enabled(source_name: str) -> bool:
            if source_name in buf_context.sources:
                spec = buf_context.sources.get(source_name)
                if spec is not None:
                    enabled = spec.enabled
                    if enabled is not None:
                        return enabled
            return f_enabled[source_name]

        limits = {
            **{
                name: fact.limit for name, fact in factories.items() if is_enabled(name)
            },
            cache_opt.source_name: cache_opt.limit,
        }
        max_wait = max(
            *(fact.timeout for name, fact in factories.items() if is_enabled(name)), 0,
        )

        go = context.line_before and not context.line_before.isspace()
        if go or options.force:

            async def gen() -> AsyncIterator[FuzzyStep]:
                source_gen = tuple(
                    source(context, s_context)
                    for name, source in sources.items()
                    if is_enabled(name)
                )
                for steps in as_completed(source_gen):
                    for step in await steps:
                        yield fuzzify(context, step=step, options=match_opt)

            async def cont() -> Sequence[FuzzyStep]:
                return [step async for step in gen()]

            cached, steps = await gather(pull(context, max_wait), cont())
            push(context, steps)
            all_steps = chain(steps, cached)

            return position, fuzzy(all_steps, options=match_opt, limits=limits)
        else:
            return position, iter(())

    chans: Dict[str, Optional[Queue]] = {name: chan for name, _, chan in src_gen}

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
