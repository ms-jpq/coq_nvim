from asyncio import Queue
from collections import defaultdict
from dataclasses import dataclass
from itertools import count
from typing import (
    Any,
    AsyncIterator,
    Callable,
    Dict,
    Iterator,
    Optional,
    Sequence,
    Tuple,
    Union,
    cast,
)

from pynvim import Nvim

from .lsp_pkgs.snippet import ParseError, parse_snippet
from ..shared.types import Completion, Context, LEdit, Position, Seed, Source
from .pkgs.nvim import call, print
from .pkgs.shared import normalize, parse_common_affix


@dataclass(frozen=True)
class ParsedRow:
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str


async def init_lua(nvim: Nvim) -> Tuple[Dict[int, str], Dict[int, str]]:
    def cont() -> Tuple[Dict[str, int], Dict[str, int]]:
        nvim.api.exec_lua("fancy_completion_lsp = require 'fancy-completion/lsp'", ())
        entry_kind = nvim.api.exec_lua(
            "return fancy_completion_lsp.list_entry_kind()", ()
        )
        insert_kind = nvim.api.exec_lua(
            "return fancy_completion_lsp.list_insert_kind()", ()
        )
        return entry_kind, insert_kind

    entry_kind, insert_kind = await call(nvim, cont)
    elookup = defaultdict(lambda: "Unknown", ((v, k) for k, v in entry_kind.items()))
    ilookup = defaultdict(lambda: "PlainText", ((v, k) for k, v in insert_kind.items()))
    return elookup, ilookup


async def ask(nvim: Nvim, chan: Queue, pos: Position, uid: int) -> Optional[Any]:
    def cont() -> None:
        nvim.api.exec_lua(
            "fancy_completion_lsp.list_comp_candidates(...)", (uid, pos.row, pos.col)
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


def row_parser(
    context: Context, insert_lookup: Dict[int, str]
) -> Callable[[Dict[str, Any]], ParsedRow]:
    def parse(row: Dict[str, Any]) -> ParsedRow:
        require_parse = is_snippet(row, insert_lookup)
        text = parse_text(row)
        if require_parse:
            new_prefix, new_suffix = parse_snippet(context, text=text)
            snippet_text = new_prefix + new_suffix
            match_normalized = normalize(snippet_text)
            old_prefix, old_suffix = parse_common_affix(
                context, match_normalized=match_normalized,
            )
            parsed = ParsedRow(
                old_prefix=old_prefix,
                new_prefix=new_prefix,
                old_suffix=old_suffix,
                new_suffix=new_suffix,
            )
            return parsed
        else:
            match_normalized = normalize(text)
            old_prefix, old_suffix = parse_common_affix(
                context, match_normalized=match_normalized,
            )
            parsed = ParsedRow(
                old_prefix=old_prefix,
                new_prefix=text,
                old_suffix=old_suffix,
                new_suffix="",
            )
            return parsed

    return parse


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
    parse = row_parser(context=context, insert_lookup=insert_lookup)

    for row in rows:
        label = row.get("label")
        sortby = row.get("sortText")
        r_kind = row.get("kind")
        kind = entry_lookup[r_kind] if r_kind else None
        doc = parse_documentation(row.get("documentation"))
        edits = parse_textedit(row)

        parsed = parse(row)

        yield Completion(
            position=position,
            old_prefix=parsed.old_prefix,
            new_prefix=parsed.new_prefix,
            old_suffix=parsed.old_suffix,
            new_suffix=parsed.new_suffix,
            label=label,
            sortby=sortby,
            kind=kind,
            doc=doc,
            ledits=edits,
        )


async def main(nvim: Nvim, chan: Queue, seed: Seed) -> Source:
    id_gen = count()
    entry_kind, insert_kind = await init_lua(nvim)

    async def source(context: Context) -> AsyncIterator[Completion]:
        uid = next(id_gen)
        resp = await ask(nvim, chan=chan, pos=context.position, uid=uid)
        rows = parse_resp_to_rows(resp)
        try:
            for row in parse_rows(
                rows,
                context=context,
                entry_lookup=entry_kind,
                insert_lookup=insert_kind,
            ):
                yield row
        except ParseError as e:
            await print(nvim, e)

    return source
