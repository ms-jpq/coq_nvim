from random import shuffle
from typing import Any, Mapping, MutableSequence, Optional, Sequence, cast

from pynvim_pp.logging import log
from std2.pickle.decoder import _new_parser

from ..shared.types import (
    UTF16,
    Completion,
    Doc,
    Edit,
    Extern,
    RangeEdit,
    SnippetEdit,
    SnippetGrammar,
    SnippetRangeEdit,
)
from .protocol import PROTOCOL
from .types import CompletionItem, CompletionResponse, LSPcomp, MarkupContent, TextEdit


def _falsy(thing: Any) -> bool:
    return thing is None or thing == False or thing == 0 or thing == "" or thing == b""


_item_parser = _new_parser(CompletionItem, path=(), strict=False, decoders=())


def _range_edit(fallback: str, edit: TextEdit) -> RangeEdit:
    begin = edit.range.start.line, edit.range.start.character
    end = edit.range.end.line, edit.range.end.character
    re = RangeEdit(
        new_text=edit.newText, fallback=fallback, begin=begin, end=end, encoding=UTF16
    )
    return re


def _primary(item: CompletionItem) -> Edit:
    fallback = Edit(new_text=item.insertText or item.label)
    if PROTOCOL.InsertTextFormat.get(item.insertTextFormat) == "Snippet":
        if isinstance(item.textEdit, TextEdit):
            re = _range_edit(fallback.new_text, edit=item.textEdit)

            return SnippetRangeEdit(
                grammar=SnippetGrammar.lsp,
                new_text=re.new_text,
                fallback=re.fallback,
                begin=re.begin,
                end=re.end,
                encoding=re.encoding,
            )
        else:
            return SnippetEdit(grammar=SnippetGrammar.lsp, new_text=fallback.new_text)
    else:
        if isinstance(item.textEdit, TextEdit):
            return _range_edit(fallback.new_text, edit=item.textEdit)
        else:
            return fallback


def _doc(item: CompletionItem) -> Optional[Doc]:
    if isinstance(item.documentation, MarkupContent):
        return Doc(text=item.documentation.value, syntax=item.documentation.kind)
    elif isinstance(item.documentation, str):
        return Doc(text=item.documentation, syntax="")
    elif item.detail:
        return Doc(text=item.detail, syntax="")
    else:
        return None


def parse_item(
    include_extern: bool, short_name: str, weight_adjust: float, item: Any
) -> Optional[Completion]:
    go, parsed = _item_parser(item)
    if not go:
        log.warn("%s", parsed)
        return None
    else:
        assert isinstance(parsed, CompletionItem)
        p_edit = _primary(parsed)
        r_edits = tuple(
            _range_edit("", edit=edit) for edit in (parsed.additionalTextEdits or ())
        )
        kind = PROTOCOL.CompletionItemKind.get(item.get("kind"), "")
        doc = _doc(parsed)
        extern = (Extern.lsp, item) if include_extern else None
        comp = Completion(
            source=short_name,
            weight_adjust=weight_adjust,
            label=parsed.label,
            primary_edit=p_edit,
            secondary_edits=r_edits,
            sort_by=parsed.filterText or p_edit.new_text,
            kind=kind,
            doc=doc,
            icon_match=kind,
            extern=extern,
        )
        return comp


def parse(
    include_extern: bool,
    short_name: str,
    weight_adjust: float,
    resp: CompletionResponse,
) -> LSPcomp:
    if _falsy(resp):
        return LSPcomp(local_cache=True, items=iter(()))

    elif isinstance(resp, Mapping):
        is_complete = _falsy(resp.get("isIncomplete"))

        if not isinstance((items := resp.get("items")), Sequence):
            return LSPcomp(local_cache=is_complete, items=iter(()))

        else:
            shuffle(cast(MutableSequence, items))
            comps = (
                co1
                for item in items
                if (
                    co1 := parse_item(
                        include_extern,
                        short_name=short_name,
                        weight_adjust=weight_adjust,
                        item=item,
                    )
                )
            )
            return LSPcomp(local_cache=is_complete, items=comps)

    elif isinstance(resp, Sequence) and not isinstance(cast(Any, resp), str):
        shuffle(cast(MutableSequence, resp))
        comps = (
            co2
            for item in resp
            if (
                co2 := parse_item(
                    include_extern,
                    short_name=short_name,
                    weight_adjust=weight_adjust,
                    item=item,
                )
            )
        )

        return LSPcomp(local_cache=True, items=comps)

    else:
        msg = f"Unknown LSP resp -- {type(resp)}"
        log.warn("%s", msg)

        return LSPcomp(local_cache=False, items=iter(()))
