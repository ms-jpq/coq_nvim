from asyncio import Queue
from itertools import count
from typing import (
    Any,
    AsyncIterator,
    Dict,
    Iterator,
    Optional,
    Sequence,
    Tuple,
    Union,
    cast,
)

from pkgs.nvim import call
from pkgs.types import Position, Source, SourceCompletion, SourceFeed, SourceSeed
from pynvim import Nvim


async def init_lua(nvim: Nvim) -> Tuple[Dict[str, int], Dict[str, int]]:
    def cont() -> Tuple[Dict[str, int], Dict[str, int]]:
        nvim.api.exec_lua("fast_comp = require 'fast_comp'", ())
        entry_kind = nvim.api.exec_lua("return fast_comp.list_entry_kind()", ())
        insert_kind = nvim.api.exec_lua("return fast_comp.list_insert_kind()", ())
        return entry_kind, insert_kind

    return await call(nvim, cont)


async def ask(nvim: Nvim, chan: Queue, pos: Position, uid: int) -> Optional[Any]:
    row = pos.row - 1
    col = pos.col

    def cont() -> None:
        nvim.api.exec_lua("fast_comp.list_comp_candidates(...)", (uid, row, col))

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
            return None
    else:
        raise ValueError(f"unknown LSP doc - {doc}")


def parse_rows(
    rows: Sequence[Dict[str, Any]],
    entry_kind_lookup: Dict[int, str],
    insert_kind_lookup: Dict[int, str],
    prefix: str,
) -> Iterator[SourceCompletion]:
    pl = len(prefix)
    for row in rows:
        txt = parse_text(row)
        if txt.startswith(prefix) and txt != prefix:
            text = txt[pl:]
            label = row["label"]
            sortby = row.get("sortText")
            kind = entry_kind_lookup.get(row.get("kind"), "Unknown")
            doc = parse_documentation(row.get("documentation"))
            yield SourceCompletion(
                text=text, label=label, sortby=sortby, kind=kind, doc=doc
            )


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    id_gen = count()
    entry_kind, insert_kind = await init_lua(nvim)
    entry_kind_lookup = {v: k for k, v in entry_kind.items()}
    insert_kind_lookup = {v: k for k, v in insert_kind.items()}

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        uid = next(id_gen)
        resp = await ask(nvim, chan=chan, pos=feed.position, uid=uid)
        rows = parse_resp_to_rows(resp)
        for row in parse_rows(
            rows,
            entry_kind_lookup=entry_kind_lookup,
            insert_kind_lookup=insert_kind_lookup,
            prefix=feed.prefix,
        ):
            yield row

    return source
