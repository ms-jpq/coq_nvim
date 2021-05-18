from collections import defaultdict
from dataclasses import dataclass
from typing import Any, Iterator, Mapping, Optional, Sequence, Tuple, Union, cast

from pynvim import Nvim

from ..shared.chan import Chan
from ..shared.comm import make_ch, schedule
from ..shared.core import run_forever
from ..shared.nvim import call
from ..shared.types import (
    Channel,
    ChannelClosed,
    Completion,
    Context,
    LEdit,
    Position,
    SEdit,
    Seed,
    Snippet,
    Source,
    SourceChans,
)

NAME = "lsp"
SNIPPET_TYPE = "lsp"


@dataclass(frozen=True)
class Config:
    pass


async def init_lua(nvim: Nvim) -> Tuple[Mapping[int, str], Mapping[int, str]]:
    def cont() -> Tuple[Mapping[str, int], Mapping[str, int]]:
        nvim.api.exec_lua("Coq_lsp = require 'Coq/lsp'", ())
        entry_kind = nvim.api.exec_lua("return Coq_lsp.list_entry_kind()", ())
        insert_kind = nvim.api.exec_lua("return Coq_lsp.list_insert_kind()", ())
        return entry_kind, insert_kind

    entry_kind, insert_kind = await call(nvim, cont)
    elookup = defaultdict(lambda: "Unknown", ((v, k) for k, v in entry_kind.items()))
    ilookup = defaultdict(lambda: "PlainText", ((v, k) for k, v in insert_kind.items()))
    return elookup, ilookup


async def ask(nvim: Nvim, context: Context, uid: int) -> None:
    row = context.position.row
    col = context.position.col

    def cont() -> None:
        nvim.api.exec_lua(
            "Coq_lsp.list_comp_candidates(...)",
            (uid, row, col),
        )

    await call(nvim, cont)


def is_snippet(row: Mapping[str, Any], insert_lookup: Mapping[int, str]) -> bool:
    fmt = row.get("insertTextFormat")
    return insert_lookup[cast(int, fmt)] != "PlainText"


def parse_text(row: Mapping[str, Any]) -> str:
    new_text = row.get("textEdit", {}).get("newText")
    insert_txt = row.get("insertText")
    if new_text is not None:
        return new_text
    elif insert_txt is not None:
        return insert_txt
    else:
        return row["label"]


def parse_documentation(doc: Union[str, Mapping[str, Any], None]) -> Optional[str]:
    tp = type(doc)
    if doc is None:
        return None
    elif tp is str:
        return cast(str, doc)
    elif tp is dict:
        val = cast(Mapping[str, Any], doc).get("value")
        if type(val) is str:
            return val
        else:
            return None
    else:
        raise ValueError(f"unknown LSP doc - {doc}")


def parse_textedit(row: Mapping[str, Any]) -> Sequence[LEdit]:
    edits = (row.get("textEdit"), *row.get("additionalTextEdits", ()))

    def cont() -> Iterator[LEdit]:
        for edit in edits:
            if type(edit) is dict:
                e = cast(Mapping[str, Any], edit)
                new_text = e["newText"]
                begin_end = e["range"]
                b = begin_end["start"]
                e = begin_end["end"]
                begin = Position(row=b["line"], col=b["character"])
                end = Position(row=e["line"], col=e["character"])
                yield LEdit(begin=begin, end=end, new_text=new_text)

    return tuple(cont())


def parse_resp_to_rows(
    resp: Any,
    context: Context,
    entry_lookup: Mapping[int, str],
    insert_lookup: Mapping[int, str],
) -> Iterator[Completion]:
    def extract() -> Sequence[Mapping[str, Any]]:
        if resp is None:
            return ()
        elif type(resp) is dict:
            return resp["items"]
        elif type(resp) is list:
            return resp
        else:
            raise ValueError(f"unknown LSP resp - {type(resp)}")

    for row in extract():
        label = row.get("label")
        sortby = row.get("sortText")
        r_kind = row.get("kind")
        kind = entry_lookup[r_kind] if r_kind else None
        text = parse_text(row)
        doc = parse_documentation(row.get("documentation"))
        edits = parse_textedit(row)
        require_parse = is_snippet(row, insert_lookup)

        sedit = SEdit(
            new_text=text,
        )

        snippet = (
            Snippet(kind=SNIPPET_TYPE, match=label or text, content=text)
            if require_parse
            else None
        )
        yield Completion(
            position=context.position,
            label=label,
            sortby=sortby,
            kind=kind,
            doc=doc,
            sedit=sedit,
            ledits=edits,
            snippet=snippet,
        )


async def main(nvim: Nvim, seed: Seed) -> Source:
    send_ch, recv_ch = make_ch(Context, Channel[Completion])
    entry_kind, insert_kind = await init_lua(nvim)

    ask_ch, reply_ch = make_ch(Context, Any)
    req = schedule(ask=ask_ch, reply=reply_ch)

    async def background_update() -> None:
        async for uid, context in ask_ch:
            await ask(nvim, context=context, uid=uid)

    async def ooda() -> None:
        async for uid, context in send_ch:
            async with Chan[Completion]() as ch:
                await recv_ch.send((uid, ch))

                resp = await req(context)

                for comp in parse_resp_to_rows(
                    resp,
                    context=context,
                    entry_lookup=entry_kind,
                    insert_lookup=insert_kind,
                ):
                    try:
                        await ch.send(comp)
                    except ChannelClosed:
                        break

    run_forever(background_update, ooda)
    return SourceChans(comm_ch=reply_ch, send_ch=send_ch, recv_ch=recv_ch)
