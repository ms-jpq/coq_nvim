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

from pynvim import Nvim

from .pkgs.fc_types import Position, Source, SourceCompletion, SourceFeed, SourceSeed
from .pkgs.nvim import call
from .pkgs.shared import normalize, parse_common_affix


async def init_lua(nvim: Nvim) -> Tuple[Dict[str, int], Dict[str, int]]:
    def cont() -> Tuple[Dict[str, int], Dict[str, int]]:
        nvim.api.exec_lua("fancy_completion_lsp = require 'fancy-completion/lsp'", ())
        entry_kind = nvim.api.exec_lua(
            "return fancy_completion_lsp.list_entry_kind()", ()
        )
        insert_kind = nvim.api.exec_lua(
            "return fancy_completion_lsp.list_insert_kind()", ()
        )
        return entry_kind, insert_kind

    return await call(nvim, cont)


async def ask(nvim: Nvim, chan: Queue, pos: Position, uid: int) -> Optional[Any]:
    row = pos.row - 1
    col = pos.col

    def cont() -> None:
        nvim.api.exec_lua(
            "fancy_completion_lsp.list_comp_candidates(...)", (uid, row, col)
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


def parse_snippet(snippet: str) -> str:
    pass


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
    feed: SourceFeed,
    entry_kind_lookup: Dict[int, str],
    insert_kind_lookup: Dict[int, str],
) -> Iterator[SourceCompletion]:
    position = feed.position
    before, after = feed.context.line_before, feed.context.line_after
    before_normalized, after_normalized = (
        feed.context.line_before_normalized,
        feed.context.line_after_normalized,
    )

    for row in rows:
        label = row.get("label")
        sortby = row.get("sortText")
        r_kind = row.get("kind")
        kind = entry_kind_lookup.get(r_kind, "Unknown") if r_kind else None
        doc = parse_documentation(row.get("documentation"))

        text = parse_text(row)
        match_normalized = normalize(text)
        old_prefix, old_suffix = parse_common_affix(
            before=before,
            after=after,
            before_normalized=before_normalized,
            after_normalized=after_normalized,
            match_normalized=match_normalized,
        )

        if old_prefix + old_suffix != text:
            yield SourceCompletion(
                position=position,
                old_prefix=old_prefix,
                new_prefix=text,
                old_suffix=old_suffix,
                new_suffix="",
                label=label,
                sortby=sortby,
                kind=kind,
                doc=doc,
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
            feed=feed,
            entry_kind_lookup=entry_kind_lookup,
            insert_kind_lookup=insert_kind_lookup,
        ):
            yield row

    return source
