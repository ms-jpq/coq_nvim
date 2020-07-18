from asyncio import Queue
from itertools import count
from typing import Any, AsyncIterator, Dict, Iterator, Optional, Sequence, Union, cast

from pkgs.nvim import call
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
    elif type(resp) is dict:
        return resp["items"]
    elif type(resp) is list:
        return resp
    else:
        raise ValueError(f"unknown LSP resp - {type(resp)}")


def parse_text(row: Dict[str, Any]) -> str:
    new_text = row.get("textEdit", {}).get("newText")
    insert_txt = row.get("insertText")
    if new_text is not None:
        return new_text
    elif insert_txt is not None:
        return insert_txt
    else:
        return row["label"]


def parse_documentation(doc: Union[str, Dict[str, Any], None]) -> Optional[str]:
    tp = type(doc)
    if doc is None:
        return None
    elif tp is str:
        return cast(str, doc)
    elif tp is dict:
        val = cast(Dict[str, Any], doc).get("value")
        if type(val) is str:
            return val
        else:
            raise ValueError(f"unknown LSP doc - {doc}")
    else:
        raise ValueError(f"unknown LSP doc - {doc}")


def parse_rows(
    rows: Sequence[Dict[str, Any]], prefix: str
) -> Iterator[SourceCompletion]:
    pl = len(prefix)
    for row in rows:
        txt = parse_text(row)
        if txt.startswith(prefix) and txt != prefix:
            text = txt[pl:]
            label = row["label"]
            sortby = row.get("sortText")
            doc = parse_documentation(row.get("documentation"))
            yield SourceCompletion(text=text, label=label, sortby=sortby, doc=doc)


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    id_gen = count()
    await init_lua(nvim)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        uid = next(id_gen)
        resp = await ask(nvim, chan=chan, pos=feed.position, uid=uid)
        rows = parse_resp_to_rows(resp)
        for row in parse_rows(rows, prefix=feed.prefix):
            yield row

    return source
