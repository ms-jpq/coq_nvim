from asyncio import Queue
from itertools import count
from typing import Any, AsyncIterator, Dict, Optional, Sequence, Union, cast

from pkgs.nvim import call, print
from pkgs.types import Position, Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


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


def parse_resp_to_rows(resp: Any) -> Sequence[Any]:
    if resp is None:
        return ()
    elif type(resp) == dict:
        return resp["items"]
    else:
        return (resp,)


def parse_documentation(doc: Union[str, Dict[str, Any], None]) -> Optional[str]:
    if doc is None:
        return None
    elif type(doc) is str:
        return cast(str, doc)
    elif type(doc) is dict:
        val = cast(Dict[str, Any], doc).get("value")
        if type(val) is str:
            return val
        else:
            return None
    else:
        return None


def parse_row(row: Dict[str, Any]) -> SourceCompletion:
    text = row["insertText"]
    label = row["label"]
    doc = parse_documentation(row.get("documentation"))
    return SourceCompletion(text=text, label=label, doc=doc)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    id_gen = count()
    await init_lua(nvim)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        uid = next(id_gen)
        resp = await ask(nvim, chan=chan, pos=feed.position, uid=uid)
        rows = parse_resp_to_rows(resp)
        for row in rows:
            yield parse_row(row)

    return source
