from asyncio import Queue
from dataclasses import dataclass
from itertools import count
from typing import Any, AsyncIterator, Sequence

from pkgs.nvim import call, print
from pkgs.types import Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


@dataclass(frozen=True)
class Row:
    label: str
    kind: int
    sortText: str
    insertText: str
    documentation: str
    detail: str


async def init_lua(nvim: Nvim) -> None:
    def cont() -> None:
        nvim.api.exec_lua("fast_comp = require 'fast_comp'", ())

    await call(nvim, cont)


async def ask(nvim: Nvim, chan: Queue, uid: int) -> Sequence[Any]:
    def cont() -> None:
        nvim.api.exec_lua("fast_comp.list_comp_candidates(...)", (uid,))

    await call(nvim, cont)
    while True:
        rid, rows = await chan.get()
        if rid == uid:
            return rows


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    id_gen = count()
    await init_lua(nvim)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        uid = next(id_gen)
        raw_rows = await ask(nvim, chan=chan, uid=uid)
        for raw in raw_rows:
            row = Row(**raw)
            yield SourceCompletion(
                text=row.insertText,
                label=row.label,
                sortby=row.sortText,
                doc=row.documentation,
            )

    return source
