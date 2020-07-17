from asyncio import Queue
from dataclasses import dataclass
from itertools import count
from typing import Any, AsyncIterator, Iterator, Optional, Sequence

from pkgs.nvim import call, print
from pkgs.types import Position, Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


@dataclass(frozen=True)
class Resp:
    isIncomplete: bool
    items: Sequence[Any]


@dataclass(frozen=True)
class Row:
    label: str
    kind: int
    sortText: str
    insertText: str
    documentation: str
    detail: str
    commitCharacters: Optional[Sequence[str]] = None
    data: Optional[str] = None


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("fast_comp = require 'fast_comp'", ())

    await call(nvim, cont)


async def ask(nvim: Nvim, chan: Queue, pos: Position, uid: int) -> Optional[Any]:
    def cont() -> None:
        nvim.api.exec_lua(
            "fast_comp.list_comp_candidates(...)", (uid, pos.row, pos.col)
        )

    await call(nvim, cont)
    while True:
        rid, resp = await chan.get()
        if rid == uid:
            return resp


async def parse_lsp(nvim, resp: Any) -> Iterator[SourceCompletion]:
    rp = Resp(**resp)
    for item in rp.items:
        row = Row(**item)
        yield SourceCompletion(text=row.insertText, label=row.label)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    id_gen = count()
    await init_lua(nvim)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        uid = next(id_gen)
        resp = await ask(nvim, chan=chan, pos=feed.position, uid=uid)
        if not resp:
            return
        else:
            async for row in parse_lsp(nvim, resp):
                yield row

    return source
