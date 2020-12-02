from asyncio import Event, gather
from dataclasses import dataclass
from itertools import chain
from os import linesep
from ..shared.chan import Chan
from typing import AsyncIterator, Iterator, Sequence, Set

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.common import NvimError

from ..shared.nvim import call
from ..shared.parse import coalesce
from ..shared.types import Completion, Context, SEdit, Seed, SourceChans
from .pkgs.nvim import autocmd
from .pkgs.scheduler import schedule
from .pkgs.sql import new_db

NAME = "buffers"


@dataclass(frozen=True)
class Config:
    polling_rate: float
    prefix_matches: int
    max_length: int


def buf_gen(nvim: Nvim) -> Iterator[Buffer]:
    seen: Set[str] = set()
    buffers: Sequence[Buffer] = nvim.api.list_bufs()
    for buf in buffers:
        try:
            filename = nvim.api.buf_get_name(buf)
        except NvimError:
            pass
        else:
            if filename not in seen:
                seen.add(filename)
                yield buf


def buf_get_lines(nvim: Nvim, buf: Buffer) -> Sequence[str]:
    try:
        return nvim.api.buf_get_lines(buf, 0, -1, True)
    except NvimError:
        return ()


async def buffer_chars(nvim: Nvim) -> Sequence[str]:
    def cont() -> Sequence[str]:
        lines = tuple(
            line for buf in buf_gen(nvim) for line in buf_get_lines(nvim, buf=buf)
        )
        return lines

    try:
        lines = await call(nvim, cont)
    except NvimError:
        return ()
    else:
        chars = tuple(char for line in lines for char in chain(line, linesep))
        return chars


async def main(nvim: Nvim, seed: Seed) -> SourceChans:
    comm = Chan[Any]()
    nvim, chan = comm.nvim, comm.chan
    config = Config(**seed.config)
    ch = Event()
    prefix_matches, max_length, unifying_chars = (
        config.prefix_matches,
        config.max_length,
        seed.match.unifying_chars,
    )

    db = DB()
    await db.init()

    await autocmd(
        nvim,
        name="buffers",
        events=("TextChanged", "TextChangedI", "BufEnter"),
        arg_eval=("'add'",),
    )

    async def ooda() -> None:
        while True:
            action, *_ = await chan.get()
            ch.set()

    async def background_update() -> None:
        async for _ in schedule(ch, min_time=0.0, max_time=config.polling_rate):
            chars, _ = await gather(buffer_chars(nvim), db.depopulate())
            words = coalesce(
                chars, max_length=max_length, unifying_chars=unifying_chars
            )
            await db.populate(words)

    async def source(context: Context) -> AsyncIterator[Completion]:
        position = context.position
        words = db.query(context, prefix_matches=prefix_matches)
        async for word in words:
            sedit = SEdit(new_text=word)
            yield Completion(position=position, sedit=sedit)

    run_forever(nvim, thing=ooda)
    run_forever(nvim, thing=background_update)
    return source
