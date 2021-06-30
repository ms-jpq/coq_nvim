from os import linesep
from typing import Any, Optional, Sequence, Tuple, cast

from pynvim_pp.logging import log
from std2.pickle import DecodeError, decode

from ..shared.types import Completion, Doc, Edit, RangeEdit, SnippetEdit
from .protocol import LSProtocol
from .types import CompletionItem, CompletionList, MarkupContent, Resp, TextEdit


def _range_edit(edit: TextEdit) -> RangeEdit:
    begin = edit.range.start.line, edit.range.end.character
    end = edit.range.end.line, edit.range.end.character
    return RangeEdit(new_text=edit.newText, begin=begin, end=end)


def _primary(client: LSProtocol, item: CompletionItem) -> Edit:
    fmt = None if item.insertTextFormat is None else str(item.insertTextFormat)

    if client.InsertTextFormat.get(cast(Any, fmt)) == "Snippet":
        if isinstance(item.textEdit, TextEdit):
            new_text = item.textEdit.newText
        else:
            new_text = item.insertText or item.label
        return SnippetEdit(grammar="lsp", new_text=new_text)
    elif isinstance(item.textEdit, TextEdit):
        return _range_edit(item.textEdit)
    else:
        return Edit(new_text=item.insertText or item.label)


def doc(item: CompletionItem) -> Optional[Doc]:
    if isinstance(item.documentation, MarkupContent):
        return Doc(text=item.documentation.value, syntax=item.documentation.kind)
    elif isinstance(item.documentation, str):
        return Doc(text=item.documentation, syntax="")
    elif item.detail:
        return Doc(text=item.detail, syntax="")
    else:
        return None


def _parse_item(
    short_name: str, tie_breaker: int, client: LSProtocol, item: CompletionItem
) -> Completion:
    cmp = Completion(
        source=short_name,
        tie_breaker=tie_breaker,
        label=item.label,
        primary_edit=_primary(client, item=item),
        secondary_edits=tuple(map(_range_edit, item.additionalTextEdits or ())),
        sort_by=item.filterText or "",
        kind=client.CompletionItemKind.get(
            cast(Any, None if item.kind is None else str(item.kind)), ""
        ),
        doc=doc(item),
        extern=item,
    )
    return cmp


def parse(
    short_name: str, tie_breaker: int, client: LSProtocol, reply: Any
) -> Tuple[bool, Sequence[Completion]]:
    try:
        resp: Resp = decode(Resp, reply, strict=False)
    except DecodeError as e:
        log.exception("%s", f"{reply}{linesep}{e}")
        return False, ()
    else:
        if isinstance(resp, CompletionList):
            # TODO -- resp.isIncomplete always True???
            return False, tuple(
                _parse_item(
                    short_name, tie_breaker=tie_breaker, client=client, item=item
                )
                for item in resp.items
            )
        elif isinstance(resp, Sequence):
            return False, tuple(
                _parse_item(
                    short_name, tie_breaker=tie_breaker, client=client, item=item
                )
                for item in resp
            )
        else:
            return False, ()

