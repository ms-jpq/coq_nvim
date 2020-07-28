from asyncio import Queue, gather, wait
from dataclasses import dataclass
from itertools import chain
from os import linesep
from traceback import format_exc
from typing import (
    Awaitable,
    Callable,
    Dict,
    Iterator,
    List,
    Optional,
    Sequence,
    Set,
    Tuple,
    cast,
)

from pynvim import Nvim

from ..shared.nvim import call, print
from ..shared.parse import is_sym, normalize
from ..shared.types import Context, Factory, Position
from .cache import make_cache
from .fuzzy import fuzzer
from .nvim import VimCompletion
from .types import Notification, Settings, SourceFactory, Step


@dataclass(frozen=True)
class GenOptions:
    sources: Set[str]
    force: bool = False


StepFunction = Callable[[Context], Awaitable[Sequence[Step]]]


def gen_ctx(filename: str, filetype: str, line: str, position: Position) -> Context:
    col = position.col
    line_before = line[:col]
    line_after = line[col:]

    lit = reversed(line_before)
    l_alnums: List[str] = []
    l_syms: List[str] = []
    for c in lit:
        if c.isalnum():
            l_alnums.append(c)
        else:
            if is_sym(c):
                l_syms.append(c)
            break

    for c in lit:
        if is_sym(c):
            l_syms.append(c)
        else:
            break

    rit = iter(line_after)
    r_alnums: List[str] = []
    r_syms: List[str] = []
    for c in rit:
        if c.isalnum():
            r_alnums.append(c)
        else:
            if is_sym(c):
                r_syms.append(c)
            break

    for c in rit:
        if is_sym(c):
            r_syms.append(c)
        else:
            break

    alnums_before = "".join(reversed(l_alnums))
    alnums_after = "".join(r_alnums)
    alnums = alnums_before + alnums_after

    syms_before = "".join(reversed(l_syms))
    syms_after = "".join(r_syms)
    syms = syms_before + syms_after

    line_normalized = normalize(line)
    line_before_normalized = normalize(line_before)
    line_after_normalized = normalize(line_after)
    alnums_normalized = normalize(alnums)

    return Context(
        position=position,
        filename=filename,
        filetype=filetype,
        line=line,
        line_normalized=line_normalized,
        line_before=line_before,
        line_before_normalized=line_before_normalized,
        line_after=line_after,
        line_after_normalized=line_after_normalized,
        alnums=alnums,
        alnums_before=alnums_before,
        alnums_after=alnums_after,
        syms=syms,
        syms_before=syms_before,
        syms_after=syms_after,
        alnums_normalized=alnums_normalized,
    )


async def gen_context(nvim: Nvim) -> Context:
    def fed() -> Tuple[str, str, str, Position]:
        buffer = nvim.api.get_current_buf()
        filename = nvim.api.buf_get_name(buffer)
        filetype = nvim.api.buf_get_option(buffer, "filetype")
        window = nvim.api.get_current_win()
        row, col = nvim.api.win_get_cursor(window)
        line = nvim.api.get_current_line()
        row = row - 1
        position = Position(row=row, col=col)
        return filename, filetype, line, position

    filename, filetype, line, position = await call(nvim, fed)
    context = gen_ctx(
        filename=filename, filetype=filetype, line=line, position=position
    )
    return context


async def manufacture(nvim: Nvim, factory: SourceFactory) -> Tuple[StepFunction, Queue]:
    chan: Queue = Queue()
    fact = cast(Factory, factory.manufacture)
    src = await fact(nvim, chan, factory.seed)

    async def source(context: Context) -> Sequence[Step]:
        name = factory.name
        timeout = factory.timeout
        acc: List[Step] = []

        async def cont() -> None:
            async for comp in src(context):
                text = comp.new_prefix + comp.new_suffix
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
            msg1 = f"⚠️  Completion source timed out - "
            msg2 = f"{name}, exceeded {timeout_fmt}ms{linesep}"
            await print(nvim, msg1 + msg2)
        return acc

    return source, chan


async def osha(
    nvim: Nvim, factory: SourceFactory
) -> Tuple[str, StepFunction, Optional[Queue]]:
    async def nil_steps(_: Context) -> Sequence[Step]:
        return ()

    try:
        step_fn, chan = await manufacture(nvim, factory=factory)
    except Exception as e:
        stack = format_exc()
        message = f"Error in source {factory.name}{linesep}{stack}{e}"
        await print(nvim, message, error=True)
        return factory.name, nil_steps, None
    else:

        async def o_step(context: Context) -> Sequence[Step]:
            try:
                return await step_fn(context)
            except Exception as e:
                stack = format_exc()
                message = f"Error in source {factory.name}{linesep}{stack}{e}"
                await print(nvim, message, error=True)
                return ()

        return factory.name, o_step, chan


async def merge(
    nvim: Nvim, chan: Queue, factories: Iterator[SourceFactory], settings: Settings
) -> Tuple[
    Callable[[GenOptions], Awaitable[Tuple[Position, Iterator[VimCompletion]]]],
    Callable[[], Awaitable[None]],
]:
    cache_opt = settings.cache
    facts = tuple(factories)
    limits = {
        **{fact.name: fact.limit for fact in facts},
        cache_opt.source_name: cache_opt.limit,
    }
    fuzzy = fuzzer(settings.fuzzy, limits=limits)
    src_gen = await gather(*(osha(nvim, factory=factory) for factory in facts))
    chans: Dict[str, Optional[Queue]] = {name: chan for name, _, chan in src_gen}
    sources: Dict[str, StepFunction] = {name: source for name, source, _ in src_gen}
    push, pull = make_cache(settings.fuzzy, options=cache_opt)

    async def gen(options: GenOptions) -> Tuple[Position, Iterator[VimCompletion]]:
        context = await gen_context(nvim)
        position = context.position
        go = context.line_before and not context.line_before.isspace()
        if go or options.force:
            source_gen = (
                source(context)
                for name, source in sources.items()
                if name in options.sources
            )
            max_wait = min(
                fact.timeout for fact in facts if fact.name in options.sources
            )
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
