from locale import strxfrm
from typing import Mapping, Optional, Sequence, Tuple

from ..shared.parse import lower
from ..shared.types import Completion, Doc, Edit, RangeEdit, SnippetEdit
from .protocol import PROTOCOL
from .types import CompletionItem, CompletionResponse, TextEdit


def _range_edit(edit: TextEdit) -> RangeEdit:
    begin = edit["range"]["start"]["line"], edit["range"]["end"]["character"]
    end = edit["range"]["end"]["line"], edit["range"]["end"]["character"]
    return RangeEdit(new_text=edit["newText"], begin=begin, end=end)


def _primary(item: CompletionItem) -> Edit:
    text_edit = item.get("textEdit")
    fall_back = item.get("insertText") or item.get("label") or ""

    if PROTOCOL.InsertTextFormat.get(item.get("insertTextFormat")) == "Snippet":
        if isinstance(text_edit, Mapping) and "range" in text_edit:
            new_text = text_edit.get("newText") or fall_back
        else:
            new_text = fall_back
        return SnippetEdit(grammar="lsp", new_text=new_text)
    elif isinstance(text_edit, Mapping) and "range" in text_edit:
        return _range_edit(text_edit)
    else:
        return Edit(new_text=fall_back)


def doc(item: CompletionItem) -> Optional[Doc]:
    doc = item.get("documentation")
    detail = item.get("detail")
    if isinstance(doc, Mapping):
        markup, kind = doc.get("value"), doc.get("kind")
        if markup and kind:
            return Doc(text=markup, syntax=kind)
        else:
            return None
    elif isinstance(doc, str):
        return Doc(text=doc, syntax="")
    elif detail:
        return Doc(text=detail, syntax="")
    else:
        return None


def _parse_item(
    short_name: str, tie_breaker: int, item: CompletionItem
) -> Optional[Completion]:
    label = item.get("label")
    if not label:
        return None
    else:
        p_edit = _primary(item)
        cmp = Completion(
            source=short_name,
            tie_breaker=tie_breaker,
            label=label,
            sort_by=strxfrm(lower(item.get("filterText") or p_edit.new_text)),
            primary_edit=p_edit,
            secondary_edits=tuple(
                map(_range_edit, item.get("additionalTextEdits") or ())
            ),
            kind=PROTOCOL.CompletionItemKind.get(item.get("kind"), ""),
            doc=doc(item),
            extern=item,
        )
        return cmp


def parse(
    short_name: str, tie_breaker: int, resp: CompletionResponse
) -> Tuple[bool, Sequence[Completion]]:
    if isinstance(resp, Mapping):
        return resp.get("isIncomplete") not in {None, False, 0}, tuple(
            c
            for c in (
                _parse_item(short_name, tie_breaker=tie_breaker, item=item)
                for item in resp.get("items", ())
            )
            if c
        )
    elif isinstance(resp, Sequence):
        return True, tuple(
            c
            for c in (
                _parse_item(short_name, tie_breaker=tie_breaker, item=item)
                for item in resp
            )
            if c
        )
    else:
        return True, ()

