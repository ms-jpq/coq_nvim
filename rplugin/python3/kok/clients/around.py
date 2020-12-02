from asyncio import gather
from asyncio.queues import QueueFull
from dataclasses import dataclass
from itertools import chain
from os import linesep
from typing import Any, Sequence

from pynvim import Nvim
from pynvim.api.buffer import Buffer

from ..shared.chan import Chan
from ..shared.comm import make_ch, schedule
from ..shared.core import run_forever
from ..shared.nvim import call
from ..shared.parse import coalesce
from ..shared.types import (
    Channel,
    Completion,
    Context,
    Position,
    SEdit,
    Seed,
    SourceChans,
)
from .pkgs.sql import QueryParams, new_db

NAME = "around"


@dataclass(frozen=True)
class Config:
    band_size: int
    prefix_matches: int
    max_length: int


async def buffer_chars(nvim: Nvim, band_size: int, pos: Position) -> Sequence[str]:
    def cont() -> Sequence[str]:
        buffer: Buffer = nvim.api.get_current_buf()
        line_count: int = nvim.api.buf_line_count(buffer)
        min_idx, max_idx = (
            max(0, pos.row - band_size),
            min(line_count, pos.row + band_size + 1),
        )
        lines: Sequence[str] = nvim.api.buf_get_lines(buffer, min_idx, max_idx, False)
        return lines

    lines = await call(nvim, cont)
    chars = tuple(char for line in lines for char in chain(line, linesep))
    return chars


async def main(nvim: Nvim, seed: Seed) -> SourceChans:
    send_ch, recv_ch = make_ch(Context, Channel[Completion])
    config = Config(**seed.config)

    db = await new_db()
    req = schedule(ask=db.ask_ch, reply=db.reply_ch)

    async def ooda() -> None:
        async for uid, context in send_ch:
            async with Chan[Completion]() as ch:
                await recv_ch.send((uid, ch))

                position = context.position

                chars, _ = await gather(
                    buffer_chars(nvim, band_size=config.band_size, pos=position),
                    db.depop_ch.send(None),
                )
                words = coalesce(
                    chars,
                    max_length=config.max_length,
                    unifying_chars=seed.match.unifying_chars,
                )
                await db.pop_ch.send(words)

                params = QueryParams(
                    context=context, prefix_matches=config.prefix_matches
                )
                resp = await req(params)

                async for word in resp:
                    sedit = SEdit(new_text=word)
                    comp = Completion(position=position, sedit=sedit)
                    try:
                        await ch.send(comp)
                    except QueueFull:
                        break

    run_forever(ooda)

    return SourceChans(comm_ch=Chan[Any](), send_ch=send_ch, recv_ch=recv_ch)
