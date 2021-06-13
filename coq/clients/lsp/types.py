from dataclasses import dataclass
from typing import Literal, Optional, Sequence, Union

# https://microsoft.github.io/language-server-protocol/specification


@dataclass(frozen=True)
class _Position:
    line: int
    character: int


@dataclass(frozen=True)
class _Range:
    start: _Position
    end: _Position


@dataclass(frozen=True)
class TextEdit:
    newText: str
    range: _Range


@dataclass(frozen=True)
class _InsertReplaceEdit:
    newText: str
    insert: _Range
    replace: _Range


_CompletionItemKind = int


@dataclass(frozen=True)
class _MarkupContent:
    kind: Union[Literal["plaintext", "markdown"], str]
    value: str


@dataclass(frozen=True)
class _InsertTextFormat:
    pass


@dataclass(frozen=True)
class CompletionItem:
    label: str
    additionalTextEdits: Optional[Sequence[TextEdit]] = None
    detail: Optional[str] = None
    documentation: Union[str, _MarkupContent, None] = None
    filterText: Optional[str] = None
    insertText: Optional[str] = None
    insertTextFormat: Optional[_InsertTextFormat] = None
    kind: Optional[_CompletionItemKind] = None
    sortText: Optional[str] = None
    textEdit: Union[TextEdit, _InsertReplaceEdit, None] = None


@dataclass(frozen=True)
class CompletionList:
    isIncomplete: bool
    items: Sequence[CompletionItem]


Resp = Union[None, Sequence[CompletionItem], CompletionList]

