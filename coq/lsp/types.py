from dataclasses import dataclass
from typing import Any, Iterator, Literal, Optional, Sequence, TypedDict, Union

from ..shared.types import Completion

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
    arguments: Optional[str]


@dataclass(frozen=True)
class CompletionItem:
    label: str
    kind: Optional[_CompletionItemKind]
    tags: Optional[Sequence[_CompletionItemTag]]

    detail: Optional[str]
    documentation: Union[str, MarkupContent, None]

    preselect: Optional[bool]
    filterText: Optional[str]
    insertText: Optional[str]
    insertTextFormat: Optional[_InsertTextFormat]
    insertTextMode: Optional[_InsertTextMode]

    additionalTextEdits: Optional[Sequence[TextEdit]]
    textEdit: Union[TextEdit, _InsertReplaceEdit, None]

    command: Command
    data: Optional[Any]


class _CompletionList(TypedDict):
    isIncomplete: bool
    items: Sequence[CompletionItem]


CompletionResponse = Union[
    Literal[None, False, 0], Sequence[CompletionItem], _CompletionList
]


@dataclass(frozen=True)
class LSPcomp:
    local_cache: bool
    items: Iterator[Completion]
