from asyncio import Queue
from collections import defaultdict
from dataclasses import dataclass
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

from ..shared.nvim import call
from ..shared.parse import normalize, parse_common_affix
from ..shared.types import (
    Comm,
    Completion,
    Context,
    LEdit,
    Position,
    Seed,
    Snippet,
    Source,
)

NAME = "lsp"


@dataclass(frozen=True)
class Config:
    enable_cancel: bool


async def init_lua(nvim: Nvim) -> Tuple[Dict[int, str], Dict[int, str]]:
    def cont() -> Tuple[Dict[str, int], Dict[str, int]]:
        nvim.api.exec_lua("nap_lsp = require 'nap/lsp'", ())
        entry_kind = nvim.api.exec_lua("return nap_lsp.list_entry_kind()", ())
        insert_kind = nvim.api.exec_lua("return nap_lsp.list_insert_kind()", ())
        return entry_kind, insert_kind

    entry_kind, insert_kind = await call(nvim, cont)
    elookup = defaultdict(lambda: "Unknown", ((v, k) for k, v in entry_kind.items()))
    ilookup = defaultdict(lambda: "PlainText", ((v, k) for k, v in insert_kind.items()))
    return elookup, ilookup


async def ask(
    nvim: Nvim, chan: Queue, context: Context, config: Config, uid: int
) -> Optional[Any]:
    enable_cancel = config.enable_cancel
    row = context.position.row
    col = context.position.col

    def cont() -> None:
        nvim.api.exec_lua(
            "nap_lsp.list_comp_candidates(...)", (uid, enable_cancel, row, col),
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


def is_snippet(row: Dict[str, Any], insert_lookup: Dict[int, str]) -> bool:
    fmt = row.get("insertTextFormat")
    return insert_lookup[cast(int, fmt)] != "PlainText"


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


def parse_textedit(row: Dict[str, Any]) -> Sequence[LEdit]:
    edits = (row.get("textEdit"), *row.get("additionalTextEdits", ()))

    def cont() -> Iterator[LEdit]:
        for edit in edits:
            if type(edit) is dict:
                e = cast(Dict[str, Any], edit)
                new_text = e["newText"]
                begin_end = e["range"]
                b = begin_end["start"]
                e = begin_end["end"]
                begin = Position(row=b["line"], col=b["character"])
                end = Position(row=e["line"], col=e["character"])
                yield LEdit(begin=begin, end=end, new_text=new_text)

    return tuple(cont())


def parse_rows(
    rows: Sequence[Dict[str, Any]],
    context: Context,
    entry_lookup: Dict[int, str],
    insert_lookup: Dict[int, str],
) -> Iterator[Completion]:
    position = context.position

    for row in rows:
        label = row.get("label")
        sortby = row.get("sortText")
        r_kind = row.get("kind")
        kind = entry_lookup[r_kind] if r_kind else None
        text = parse_text(row)
        doc = parse_documentation(row.get("documentation"))
        edits = parse_textedit(row)
        require_parse = is_snippet(row, insert_lookup)

        if require_parse:
            snippet = Snippet(kind="lsp", content=text, match=text)
            yield Completion(
                position=position,
                old_prefix="",
                new_prefix="",
                old_suffix="",
                new_suffix="",
                label=label,
                sortby=sortby,
                kind=kind,
                doc=doc,
                ledits=edits,
                snippet=snippet,
            )
        else:
            match_normalized = normalize(text)
            old_prefix, old_suffix = parse_common_affix(
                context, match_normalized=match_normalized, use_line=False,
            )

            yield Completion(
                position=position,
                old_prefix=old_prefix,
                new_prefix=text,
                old_suffix=old_suffix,
                new_suffix="",
                label=label,
                sortby=sortby,
                kind=kind,
                doc=doc,
                ledits=edits,
            )


async def main(comm: Comm, seed: Seed) -> Source:
    nvim, chan = comm.nvim, comm.chan
    config = Config(**seed.config)

    id_gen = count()
    entry_kind, insert_kind = await init_lua(nvim)

    async def source(context: Context) -> AsyncIterator[Completion]:
        uid = next(id_gen)
        resp = await ask(nvim, chan=chan, context=context, config=config, uid=uid)
        rows = parse_resp_to_rows(resp)
        for row in parse_rows(
            rows, context=context, entry_lookup=entry_kind, insert_lookup=insert_kind,
        ):
            yield row

    return source
