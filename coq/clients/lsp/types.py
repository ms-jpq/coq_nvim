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
class _TextEdit:
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
    pass


@dataclass(frozen=True)
class _InsertTextFormat:
    kind: Union[Literal["plaintext", "markdown"], str]
    value: str


@dataclass(frozen=True)
class _CompletionItem:
    label: str
    additionalTextEdits: Optional[Sequence[_TextEdit]] = None
    detail: Optional[str] = None
    documentation: Optional[Union[str, _MarkupContent]] = None
    filterText: Optional[str] = None
    insertText: Optional[str] = None
    insertTextFormat: Optional[_InsertTextFormat] = None
    kind: Optional[_CompletionItemKind] = None
    textEdit: Optional[Union[_TextEdit, _InsertReplaceEdit]] = None


@dataclass(frozen=True)
class _CompletionList:
    isIncomplete: bool
    items: Sequence[_CompletionItem]


Resp = Optional[Union[Sequence[_CompletionItem], _CompletionList]]
