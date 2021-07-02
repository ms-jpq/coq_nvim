from typing import Optional, Sequence, Tuple

from ..shared.types import Completion, Doc, Edit, RangeEdit, SnippetEdit
from .protocol import PROTOCOL
from .types import (
    CompletionItem,
    CompletionList,
    CompletionResponse,
    MarkupContent,
    TextEdit,
)


def _range_edit(edit: TextEdit) -> RangeEdit:
    begin = edit.range.start.line, edit.range.end.character
    end = edit.range.end.line, edit.range.end.character
    return RangeEdit(new_text=edit.newText, begin=begin, end=end)


def _primary(item: CompletionItem) -> Edit:
    if PROTOCOL.InsertTextFormat.get(item.insertTextFormat) == "Snippet":
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


def _parse_item(short_name: str, tie_breaker: int, item: CompletionItem) -> Completion:
    cmp = Completion(
        source=short_name,
        tie_breaker=tie_breaker,
        label=item.label,
        primary_edit=_primary(item),
        secondary_edits=tuple(map(_range_edit, item.additionalTextEdits or ())),
        sort_by=item.filterText or "",
        kind=PROTOCOL.CompletionItemKind.get(item.kind, ""),
        doc=doc(item),
        extern=item,
    )
    return cmp


def parse(
    short_name: str, tie_breaker: int, resp: CompletionResponse
) -> Tuple[bool, Sequence[Completion]]:
    if isinstance(resp, CompletionList):
        return resp.isIncomplete, tuple(
            _parse_item(short_name, tie_breaker=tie_breaker, item=item)
            for item in resp.items
        )
    elif isinstance(resp, Sequence):
        return True, tuple(
            _parse_item(short_name, tie_breaker=tie_breaker, item=item) for item in resp
        )
    else:
        return True, ()

