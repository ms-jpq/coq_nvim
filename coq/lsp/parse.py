from random import shuffle
from typing import Any, Mapping, MutableSequence, Optional, Type, Union

from pynvim_pp.logging import log
from std2.pickle.decoder import _new_parser

from ..shared.types import (
    UTF16,
    Completion,
    Doc,
    Edit,
    ExternLSP,
    ExternLUA,
    RangeEdit,
    SnippetEdit,
    SnippetGrammar,
    SnippetRangeEdit,
)
from .protocol import PROTOCOL
from .types import (
    CompletionItem,
    CompletionResponse,
    InsertReplaceEdit,
    LSPcomp,
    MarkupContent,
    TextEdit,
)


def _falsy(thing: Any) -> bool:
    return thing is None or thing == False or thing == 0 or thing == "" or thing == b""


_item_parser = _new_parser(CompletionItem, path=(), strict=False, decoders=())


def _range_edit(fallback: str, edit: Union[TextEdit, InsertReplaceEdit]) -> RangeEdit:
    if isinstance(edit, TextEdit):
        ra_start = edit.range.start
        ra_end = edit.range.end
    else:
        ra_start = edit.replace.start
        ra_end = edit.replace.end

    begin = ra_start.line, ra_start.character
    end = ra_end.line, ra_end.character

    re = RangeEdit(
        new_text=edit.newText, fallback=fallback, begin=begin, end=end, encoding=UTF16
    )
    return re


def _primary(item: CompletionItem) -> Edit:
    fallback = Edit(new_text=item.insertText or item.label)
    if PROTOCOL.InsertTextFormat.get(item.insertTextFormat) == "Snippet":
        if isinstance(item.textEdit, (TextEdit, InsertReplaceEdit)):
            re = _range_edit(fallback.new_text, edit=item.textEdit)

            return SnippetRangeEdit(
                grammar=SnippetGrammar.lsp,
                new_text=re.new_text,
                fallback=item.insertText,
                begin=re.begin,
                end=re.end,
                encoding=re.encoding,
            )
        else:
            return SnippetEdit(grammar=SnippetGrammar.lsp, new_text=fallback.new_text)
    else:
        if isinstance(item.textEdit, (TextEdit, InsertReplaceEdit)):
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
    extern_type: Union[Type[ExternLSP], Type[ExternLUA]],
    client: Optional[str],
    short_name: str,
    weight_adjust: float,
    item: Any,
) -> Optional[Completion]:
    if not item:
        return None
    else:
        go, parsed = _item_parser(item)
        if not go:
            log.warn("%s", parsed)
            return None
        else:
            assert isinstance(parsed, CompletionItem)
            p_edit = _primary(parsed)
            r_edits = tuple(
                _range_edit("", edit=edit)
                for edit in (parsed.additionalTextEdits or ())
            )
            sort_by = parsed.filterText or (
                parsed.label if isinstance(p_edit, SnippetEdit) else p_edit.new_text
            )
            kind = PROTOCOL.CompletionItemKind.get(item.get("kind"), "")
            doc = _doc(parsed)
            extern = extern_type(client=client, item=item, command=parsed.command)
            comp = Completion(
                source=short_name,
                weight_adjust=weight_adjust,
                label=parsed.label,
                primary_edit=p_edit,
                secondary_edits=r_edits,
                sort_by=sort_by,
                preselect=parsed.preselect or False,
                kind=kind,
                doc=doc,
                icon_match=kind,
                extern=extern,
            )
            return comp


def parse(
    extern_type: Union[Type[ExternLSP], Type[ExternLUA]],
    client: Optional[str],
    short_name: str,
    weight_adjust: float,
    resp: CompletionResponse,
) -> LSPcomp:
    if _falsy(resp):
        return LSPcomp(client=client, local_cache=True, items=iter(()))

    elif isinstance(resp, Mapping):
        is_complete = _falsy(resp.get("isIncomplete"))

        if not isinstance((items := resp.get("items")), MutableSequence):
            log.warn("%s", f"Unknown LSP resp -- {type(resp)}")
            return LSPcomp(client=client, local_cache=is_complete, items=iter(()))

        else:
            shuffle(items)
            comps = (
                co1
                for item in items
                if (
                    co1 := parse_item(
                        extern_type,
                        client=client,
                        short_name=short_name,
                        weight_adjust=weight_adjust,
                        item=item,
                    )
                )
            )
            return LSPcomp(client=client, local_cache=is_complete, items=comps)

    elif isinstance(resp, MutableSequence):
        shuffle(resp)
        comps = (
            co2
            for item in resp
            if (
                co2 := parse_item(
                    extern_type,
                    client=client,
                    short_name=short_name,
                    weight_adjust=weight_adjust,
                    item=item,
                )
            )
        )

        return LSPcomp(client=client, local_cache=True, items=comps)

    else:
        log.warn("%s", f"Unknown LSP resp -- {type(resp)}")
        return LSPcomp(client=client, local_cache=False, items=iter(()))
