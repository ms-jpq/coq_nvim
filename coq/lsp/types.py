from typing import Literal, Optional, Sequence, TypedDict, Union

# https://microsoft.github.io/language-server-protocol/specification


class _Position(TypedDict):
    line: int
    character: int


class _Range(TypedDict):
    start: _Position
    end: _Position


class TextEdit(TypedDict):
    newText: str
    range: _Range


class InsertReplaceEdit(TypedDict):
    newText: str
    insert: _Range
    replace: _Range


_CompletionItemKind = int


class _MarkupContent(TypedDict):
    kind: Union[Literal["plaintext", "markdown"], str]
    value: str


_InsertTextFormat = int


class CompletionItem(TypedDict):
    label: str
    additionalTextEdits: Optional[Sequence[TextEdit]]
    detail: Optional[str]
    documentation: Union[str, _MarkupContent, None]
    filterText: Optional[str]
    insertText: Optional[str]
    insertTextFormat: Optional[_InsertTextFormat]
    kind: Optional[_CompletionItemKind]
    textEdit: Union[TextEdit, InsertReplaceEdit, None]


class _CompletionList(TypedDict):
    isIncomplete: bool
    items: Sequence[CompletionItem]


CompletionResponse = Union[
    Literal[None, False, 0], Sequence[CompletionItem], _CompletionList
]
