from asyncio import Queue, gather, wait
from asyncio.tasks import as_completed
from dataclasses import dataclass
from itertools import chain
from math import inf
from os import linesep
from typing import (
    AsyncIterator,
    Awaitable,
    Callable,
    Dict,
    Iterator,
    List,
    Optional,
    Sequence,
    Set,
    Tuple,
)

from pynvim import Nvim

from ..shared.logging import log
from ..shared.nvim import print
from ..shared.parse import normalize
from ..shared.types import Comm, Completion, Context, MatchOptions, Position
from .context import gen_buf_ctx, gen_context, goahead
from .fuzzy import fuzzify, fuzzy
from .nvim import VimCompletion
from .settings import load_factories
from .types import BufferContext, Settings, SourceFactory, Step, Suggestion


@dataclass(frozen=True)
class GenOptions:
    force: bool = False


@dataclass(frozen=True)
class StepContext:
    timeout: float


@dataclass(frozen=True)
class StepReply:
    rank: int
    suggestions: Sequence[Suggestion]


StepFunction = Callable[[Context, StepContext], Awaitable[StepReply]]


def parse_match(comp: Completion) -> Tuple[str, str]:
    def cont() -> str:
        if comp.snippet:
            return comp.snippet.match
        elif comp.medit:
            return comp.medit.new_prefix + comp.medit.new_suffix
        elif comp.sedit:
            return comp.sedit.new_text
        elif comp.ledits:
            return next(iter(comp.ledits)).new_text
        else:
            msg = f"No actionable match for - {comp}"
            log.warning("%s", msg)
            return ""

    match = cont()
    normalized = normalize(match)
    return match, normalized


def gen_suggestion(
    name: str, factory: SourceFactory, context: Context, comp: Completion
) -> Suggestion:
    match, match_normalized = parse_match(comp)
    suggestion = Suggestion(
        position=context.position,
        source=name,
        source_shortname=factory.short_name,
        unique=factory.unique,
        rank=factory.rank,
        kind=comp.kind,
        doc=comp.doc,
        label=comp.label,
        sortby=comp.sortby,
        match=match,
        match_normalized=match_normalized,
        sedit=comp.sedit,
        medit=comp.medit,
        ledits=comp.ledits,
        snippet=comp.snippet,
    )
    return suggestion


async def manufacture(
    nvim: Nvim, name: str, factory: SourceFactory
) -> Tuple[StepFunction, Queue]:
    chan: Queue = Queue()
    comm = Comm(nvim=nvim, chan=chan)
    src = await factory.manufacture(comm, factory.seed)

    async def source(context: Context, s_context: StepContext) -> StepReply:
        timeout = s_context.timeout
        suggestions: List[Suggestion] = []

        async def cont() -> None:
            async for comp in src(context):
                suggestion = gen_suggestion(
                    name, factory=factory, context=context, comp=comp
                )
                suggestions.append(suggestion)

        done, pending = await wait((cont(),), timeout=timeout)
        for p in pending:
            p.cancel()
        await gather(*done)

        if pending:
            timeout_fmt = round(timeout * 1000)
            msg1 = "⚠️  Completion source timed out - "
            msg2 = f"{name}, exceeded {timeout_fmt}ms{linesep}"
            await print(nvim, msg1 + msg2)

        reply = StepReply(rank=factory.rank, suggestions=suggestions)
        return reply

    return source, chan


async def osha(
    nvim: Nvim, name: str, factory: SourceFactory, retries: int
) -> Tuple[str, StepFunction, Optional[Queue]]:
    nil_reply = StepReply(rank=0, suggestions=())

    async def nil_steps(_: Context, __: StepContext) -> StepReply:
        return nil_reply

    try:
        step_fn, chan = await manufacture(nvim, name=name, factory=factory)
    except Exception as e:
        message = f"Error in source {name}:{linesep}{e}"
        log.exception("%s", message)
        return name, nil_steps, None
    else:
        errored = 0

        async def safe_step(context: Context, s_context: StepContext) -> StepReply:
            nonlocal errored
            if errored >= retries:
                return nil_reply
            else:
                try:
                    ret = await step_fn(context, s_context)
                except Exception as e:
                    errored += 1
                    message = f"Error in source {name}:{linesep}{e}"
                    log.exception("%s", message)
                    return nil_reply
                else:
                    errored = 0
                    return ret

        return name, safe_step, chan


def buffer_opts(
    factories: Dict[str, SourceFactory],
    buf_context: BufferContext,
) -> Tuple[Set[str], Dict[str, float]]:
    def is_enabled(name: str, factory: SourceFactory) -> bool:
        if name in buf_context.sources:
            spec = buf_context.sources.get(name)
            if spec is not None:
                enabled = spec.enabled
                if enabled is not None:
                    return enabled
        return factory.enabled

    enabled: Set[str] = {
        name for name, factory in factories.items() if is_enabled(name, factory=factory)
    }

    limits = {name: fact.limit for name, fact in factories.items() if name in enabled}

    return enabled, limits


async def gen_steps(
    context: Context,
    match_opt: MatchOptions,
    timeout: float,
    futures: Iterator[Awaitable[StepReply]],
) -> Iterator[Step]:
    async def cont() -> AsyncIterator[Step]:
        for fut in as_completed(tuple(futures)):
            reply = await fut
            for suggestion in reply.suggestions:
                step = fuzzify(context, suggestion=suggestion, options=match_opt)
                yield step

    async def c1() -> Sequence[Step]:
        return [suggestion async for suggestion in cont()]

    s1 = await c1()
    return iter(s1)


async def merge(
    nvim: Nvim, settings: Settings
) -> Tuple[
    Callable[[GenOptions], Awaitable[Tuple[Position, Iterator[VimCompletion]]]],
    Dict[str, Queue],
]:
    display_opt, match_opt = settings.display, settings.match
    factories = load_factories(settings=settings)
    src_gen = await gather(
        *(
            osha(nvim, name=name, factory=factory, retries=settings.retries)
            for name, factory in factories.items()
        )
    )
    sources: Dict[str, StepFunction] = {name: source for name, source, _ in src_gen}

    async def gen(options: GenOptions) -> Tuple[Position, Iterator[VimCompletion]]:
        timeout = inf if options.force else settings.timeout
        context, buf_context = await gather(
            gen_context(nvim, options=match_opt, pos=None), gen_buf_ctx(nvim)
        )
        position = context.position
        s_context = StepContext(
            timeout=timeout,
        )
        enabled, limits = buffer_opts(factories, buf_context=buf_context)

        if options.force or goahead(context):
            source_gen = (
                source(context, s_context)
                for name, source in sources.items()
                if name in enabled
            )
            steps = await gen_steps(
                context,
                match_opt=match_opt,
                timeout=timeout,
                futures=source_gen,
            )
            comps = fuzzy(steps=steps, display_opt=display_opt, limits=limits)

            return position, comps
        else:
            return position, iter(())

    chans: Dict[str, Queue] = {name: chan for name, _, chan in src_gen if chan}
    return gen, chans
