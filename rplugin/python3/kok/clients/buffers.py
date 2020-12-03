from asyncio import  gather
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import Any, Iterator, Sequence, Set

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.common import NvimError

from ..shared.chan import Chan
from ..shared.comm import make_ch, schedule
from ..shared.core import run_forever
from ..shared.da import tiktok
from ..shared.nvim import call
from ..shared.parse import coalesce
from ..shared.types import Channel, Completion, Context, SEdit, Seed, SourceChans,ChannelClosed
from .pkgs.sql import new_db, QueryParams

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
    send_ch, recv_ch = make_ch(Context, Channel[Completion])

    config = Config(**seed.config)

    db = await new_db()
    req = schedule(ask=db.ask_ch, reply=db.reply_ch)

    async def background_update() -> None:
        async for _ in tiktok(config.polling_rate):
            chars, _ = await gather(buffer_chars(nvim), db.depop_ch.send(None))
            words = coalesce(
                chars,
                max_length=config.max_length,
                unifying_chars=seed.match.unifying_chars,
            )
            await db.pop_ch.send(words)

    async def ooda() -> None:
        async for uid, context in send_ch:
            async with Chan[Completion]() as ch:
                await recv_ch.send((uid, ch))

                params = QueryParams(
                    context=context, prefix_matches=config.prefix_matches
                )
                async with await req(params) as resp:
                    async for word in resp:
                        sedit = SEdit(new_text=word)
                        comp = Completion(position=context.position, sedit=sedit)
                        try:
                            await ch.send(comp)
                        except ChannelClosed:
                            break

    run_forever(background_update, ooda)
    return SourceChans(comm_ch=Chan[Any](), send_ch=send_ch, recv_ch=recv_ch)
