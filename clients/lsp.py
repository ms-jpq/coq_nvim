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

from .pkgs.fc_types import (
    Context,
    Position,
    Source,
    SourceCompletion,
    SourceFeed,
    SourceSeed,
)
from .pkgs.nvim import call
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
    ilookup = defaultdict(lambda: None, ((v, k) for k, v in insert_kind.items()))
    return elookup, ilookup


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


def is_snippet(row: Dict[str, Any], insert_lookup: Dict[int, str]) -> bool:
    fmt = row.get("insertTextFormat")
    return insert_lookup[fmt] != "PlainText"


def parse_snippet(context: Context, text: str) -> ParsedRow:
    dollar = False
    bracket = False
    it = iter(text)

    def pre() -> Iterator[str]:
        nonlocal dollar, bracket

        for char in it:
            if char == "$":
                dollar = True
            elif dollar:
                dollar = False
                if char == "{":
                    bracket = True
                    break
            else:
                yield char

    def post() -> Iterator[str]:
        nonlocal dollar, bracket

        for char in it:
            if char == "$":
                dollar = True
            elif dollar:
                dollar = False
                if char == "{":
                    bracket = True
            elif bracket:
                if char == "}":
                    bracket = False
            else:
                yield char

    new_prefix = "".join(pre())
    new_suffix = "".join(post())
    old_prefix = ""
    old_suffix = ""

    parsed = ParsedRow(
        old_prefix=old_prefix,
        new_prefix=new_prefix,
        old_suffix=old_suffix,
        new_suffix=new_suffix,
    )
    return parsed


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
    before, after = context.line_before, context.line_after
    before_normalized, after_normalized = (
        context.line_before_normalized,
        context.line_after_normalized,
    )

    def parse(row: Dict[str, Any]) -> ParsedRow:
        require_parse = is_snippet(row, insert_lookup)
        text = parse_text(row)
        if require_parse:
            return parse_snippet(context, text=text)
        else:
            match_normalized = normalize(text)
            old_prefix, old_suffix = parse_common_affix(
                before=before,
                after=after,
                before_normalized=before_normalized,
                after_normalized=after_normalized,
                match_normalized=match_normalized,
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


def parse_rows(
    rows: Sequence[Dict[str, Any]],
    feed: SourceFeed,
    entry_lookup: Dict[int, str],
    insert_lookup: Dict[int, str],
) -> Iterator[SourceCompletion]:
    position = feed.position
    parse = row_parser(context=feed.context, insert_lookup=insert_lookup)

    for row in rows:
        label = row.get("label")
        sortby = row.get("sortText")
        r_kind = row.get("kind")
        kind = entry_lookup[r_kind] if r_kind else None
        doc = parse_documentation(row.get("documentation"))
        parsed = parse(row)

        yield SourceCompletion(
            position=position,
            old_prefix=parsed.old_prefix,
            new_prefix=parsed.new_prefix,
            old_suffix=parsed.old_suffix,
            new_suffix=parsed.new_suffix,
            label=label,
            sortby=sortby,
            kind=kind,
            doc=doc,
        )


async def main(nvim: Nvim, chan: Queue, seed: SourceSeed) -> Source:
    id_gen = count()
    entry_kind, insert_kind = await init_lua(nvim)

    async def source(feed: SourceFeed) -> AsyncIterator[SourceCompletion]:
        uid = next(id_gen)
        resp = await ask(nvim, chan=chan, pos=feed.position, uid=uid)
        rows = parse_resp_to_rows(resp)
        for row in parse_rows(
            rows, feed=feed, entry_lookup=entry_kind, insert_lookup=insert_kind,
        ):
            yield row

    return source
