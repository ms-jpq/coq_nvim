from dataclasses import asdict
from typing import (
    AbstractSet,
    Any,
    Mapping,
    MutableMapping,
    Optional,
    Sequence,
    Type,
    Union,
)

from pynvim_pp.logging import log
from std2.pickle.decoder import _new_parser, new_decoder
from std2.types import never

from ..shared.types import (
    UTF8,
    UTF16,
    UTF32,
    Completion,
    Cursors,
    Doc,
    Edit,
    Encoding,
    ExternLSP,
    ExternLUA,
    RangeEdit,
    SnippetEdit,
    SnippetGrammar,
    SnippetRangeEdit,
)
from .protocol import LSProtocol
from .types import (
    CompletionItem,
    CompletionResponse,
    InsertReplaceEdit,
    ItemDefaults,
    LSPcomp,
    MarkupContent,
    TextEdit,
)

_FALSY = {None, False, 0, "", b""}


def _falsy(thing: Any) -> bool:
    return thing in _FALSY


_defaults_parser = new_decoder[Optional[ItemDefaults]](
    Optional[ItemDefaults], strict=False, decoders=()
)
_item_parser = _new_parser(CompletionItem, path=(), strict=False, decoders=())


def _with_defaults(defaults: ItemDefaults, item: Any) -> Any:
    if not isinstance(item, MutableMapping):
        pass
    else:
        item.setdefault("insertTextFormat", defaults.insertTextFormat)
        item.setdefault("insertTextMode", defaults.insertTextMode)
        item.setdefault("data", defaults.data)

        if isinstance(text := item.get("insertText") or item.get("label"), str) and (
            edit_range := defaults.editRange
        ):
            item.setdefault("textEdit", {"new_text": text, **asdict(edit_range)})

    return item


def _range_edit(
    encoding: Encoding,
    cursors: Cursors,
    fallback: Optional[str],
    edit: Union[TextEdit, InsertReplaceEdit],
) -> RangeEdit:
    _, u8, u16, u32 = cursors
    if encoding == UTF16:
        cursor = u16
    elif encoding == UTF8:
        cursor = u8
    elif encoding == UTF32:
        cursor = u32
    else:
        never(encoding)

    if isinstance(edit, TextEdit):
        ra_start = edit.range.start
        ra_end = edit.range.end
    else:
        ra_start = edit.replace.start
        ra_end = edit.replace.end

    begin = ra_start.line, ra_start.character
    end = ra_end.line, ra_end.character

    re = RangeEdit(
        new_text=edit.newText,
        fallback=fallback,
        begin=begin,
        end=end,
        cursor_pos=cursor,
        encoding=encoding,
    )
    return re


def _primary(
    protocol: LSProtocol, encoding: Encoding, cursors: Cursors, item: CompletionItem
) -> Edit:
    fallback = Edit(new_text=item.insertText or item.label)
    if protocol.InsertTextFormat.get(item.insertTextFormat) == "Snippet":
        if isinstance(item.textEdit, (TextEdit, InsertReplaceEdit)):
            re = _range_edit(
                encoding,
                cursors=cursors,
                fallback=item.insertText,
                edit=item.textEdit,
            )

            return SnippetRangeEdit(
                grammar=SnippetGrammar.lsp,
                new_text=re.new_text,
                fallback=re.fallback,
                begin=re.begin,
                end=re.end,
                cursor_pos=re.cursor_pos,
                encoding=re.encoding,
            )
        else:
            return SnippetEdit(grammar=SnippetGrammar.lsp, new_text=fallback.new_text)
    else:
        if isinstance(item.textEdit, (TextEdit, InsertReplaceEdit)):
            return _range_edit(
                encoding,
                cursors=cursors,
                fallback=item.insertText,
                edit=item.textEdit,
            )
        else:
            return fallback


def _adjust_indent(mode: Optional[int], edit: Edit) -> bool:
    return mode == 2 or isinstance(edit, SnippetEdit)


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
    protocol: LSProtocol,
    extern_type: Union[Type[ExternLSP], Type[ExternLUA]],
    always_on_top: Optional[AbstractSet[Optional[str]]],
    client: Optional[str],
    encoding: Encoding,
    cursors: Cursors,
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
            on_top = (
                False
                if always_on_top is None
                else (not always_on_top or client in always_on_top)
            )
            label = (
                parsed.label + (label_detail.detail or "")
                if (label_detail := parsed.labelDetails)
                else parsed.label
            )
            p_edit = _primary(protocol, encoding=encoding, cursors=cursors, item=parsed)
            adjust_indent = _adjust_indent(parsed.insertTextMode, edit=p_edit)
            r_edits = tuple(
                _range_edit(
                    encoding, cursors=(-1, -1, -1, -1), fallback=None, edit=edit
                )
                for edit in (parsed.additionalTextEdits or ())
            )
            sort_by = parsed.filterText or (
                parsed.label if isinstance(p_edit, SnippetEdit) else p_edit.new_text
            )
            kind = protocol.CompletionItemKind.get(item.get("kind"), "")
            doc = _doc(parsed)
            extern = extern_type(client=client, item=item, command=parsed.command)

            comp = Completion(
                source=short_name,
                always_on_top=on_top,
                weight_adjust=weight_adjust,
                label=label,
                primary_edit=p_edit,
                adjust_indent=adjust_indent,
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
    protocol: LSProtocol,
    extern_type: Union[Type[ExternLSP], Type[ExternLUA]],
    always_on_top: Optional[AbstractSet[Optional[str]]],
    client: Optional[str],
    encoding: Encoding,
    short_name: str,
    cursors: Cursors,
    weight_adjust: float,
    resp: CompletionResponse,
) -> LSPcomp:
    if _falsy(resp):
        return LSPcomp(client=client, local_cache=True, items=iter(()), length=0)

    elif isinstance(resp, Mapping):
        is_complete = _falsy(resp.get("isIncomplete"))

        if not isinstance((items := resp.get("items")), Sequence):
            log.warn("%s", f"Unknown LSP resp -- {type(resp)}")
            return LSPcomp(
                client=client, local_cache=is_complete, items=iter(()), length=0
            )

        else:
            defaults = _defaults_parser(resp.get("itemDefaults")) or ItemDefaults()
            length = len(items)
            comps = (
                co1
                for item in items
                if (
                    co1 := parse_item(
                        protocol,
                        extern_type=extern_type,
                        client=client,
                        encoding=encoding,
                        always_on_top=always_on_top,
                        short_name=short_name,
                        cursors=cursors,
                        weight_adjust=weight_adjust,
                        item=_with_defaults(defaults, item=item),
                    )
                )
            )

            return LSPcomp(
                client=client, local_cache=is_complete, items=comps, length=length
            )

    elif isinstance(resp, Sequence):
        defaults = ItemDefaults()
        length = len(resp)
        comps = (
            co2
            for item in resp
            if (
                co2 := parse_item(
                    protocol,
                    extern_type=extern_type,
                    always_on_top=always_on_top,
                    client=client,
                    encoding=encoding,
                    short_name=short_name,
                    cursors=cursors,
                    weight_adjust=weight_adjust,
                    item=_with_defaults(defaults, item=item),
                )
            )
        )

        return LSPcomp(client=client, local_cache=True, items=comps, length=length)

    else:
        log.warn("%s", f"Unknown LSP resp -- {type(resp)}")
        return LSPcomp(client=client, local_cache=False, items=iter(()), length=0)
