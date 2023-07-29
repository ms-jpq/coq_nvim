from dataclasses import dataclass
from typing import (
    AbstractSet,
    Any,
    Iterator,
    Literal,
    Optional,
    Sequence,
    TypedDict,
    Union,
)

from ..shared.types import Completion

# https://microsoft.github.io/language-server-protocol/specification


@dataclass(frozen=True)
class _CompletionItemLabelDetails:
    detail: Optional[str] = None
    description: Optional[str] = None


@dataclass(frozen=True)
class _Position:
    line: int
    character: int


@dataclass(frozen=True)
class _TextEdit:
    newText: str


@dataclass(frozen=True)
class _Range:
    start: _Position
    end: _Position


@dataclass(frozen=True)
class _InsertReplaceRange:
    insert: _Range
    replace: _Range


@dataclass(frozen=True)
class TextEdit(_TextEdit):
    range: _Range


@dataclass(frozen=True)
class InsertReplaceEdit(_TextEdit, _InsertReplaceRange):
    ...


_CompletionItemKind = int


@dataclass(frozen=True)
class MarkupContent:
    kind: Union[Literal["plaintext", "markdown"], str]
    value: str


_InsertTextFormat = int
_CompletionItemTag = int
_InsertTextMode = int


@dataclass(frozen=True)
class Command:
    title: str
    command: str
    arguments: Optional[Any] = None


@dataclass(frozen=True)
class CompletionItem:
    label: str
    labelDetails: Optional[_CompletionItemLabelDetails] = None

    kind: Optional[_CompletionItemKind] = None
    tags: Optional[Sequence[_CompletionItemTag]] = None

    detail: Optional[str] = None
    documentation: Union[str, MarkupContent, None] = None

    preselect: Optional[bool] = None
    filterText: Optional[str] = None

    insertText: Optional[str] = None
    insertTextFormat: Optional[_InsertTextFormat] = None
    insertTextMode: Optional[_InsertTextMode] = None

    textEdit: Union[TextEdit, InsertReplaceEdit, None] = None
    additionalTextEdits: Optional[Sequence[TextEdit]] = None

    command: Optional[Command] = None
    data: Optional[Any] = None


@dataclass(frozen=True)
class ItemDefaults:
    commitCharacters: Optional[AbstractSet[str]] = frozenset()
    editRange: Union[_Range, _InsertReplaceRange, None] = None
    insertTextFormat: Optional[_InsertTextFormat] = None
    insertTextMode: Optional[_InsertTextMode] = None
    data: Optional[Any] = None


class _CompletionList(TypedDict):
    isIncomplete: bool
    items: Sequence[CompletionItem]
    itemDefaults: Optional[ItemDefaults]


CompletionResponse = Union[
    Literal[None, False, 0], Sequence[CompletionItem], _CompletionList
]


@dataclass(frozen=True)
class LSPcomp:
    client: Optional[str]
    local_cache: bool
    items: Iterator[Completion]
    length: int
