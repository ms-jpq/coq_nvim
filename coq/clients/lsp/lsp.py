from dataclasses import dataclass
from typing import Optional, Sequence, Union


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
    pass


@dataclass(frozen=True)
class _CompletionItem:
    label: str
    kind: Optional[_CompletionItemKind] = None
    detail: Optional[str] = None
    documentation: Optional[Union[str, _MarkupContent]] = None
    filterText: Optional[str] = None
    insertText: Optional[str] = None
    insertTextFormat: Optional[_InsertTextFormat] = None
    textEdit: Optional[Union[_TextEdit, _InsertReplaceEdit]] = None
    additionalTextEdits: Optional[Sequence[_TextEdit]] = None


# async def init_lua(nvim: Nvim) -> Tuple[Mapping[int, str], Mapping[int, str]]:
# def cont() -> Tuple[Mapping[str, int], Mapping[str, int]]:
# nvim.api.exec_lua("Coq_lsp = require 'Coq/lsp'", ())
# entry_kind = nvim.api.exec_lua("return Coq_lsp.list_entry_kind()", ())
# insert_kind = nvim.api.exec_lua("return Coq_lsp.list_insert_kind()", ())
# return entry_kind, insert_kind

# entry_kind, insert_kind = await call(nvim, cont)
# elookup = defaultdict(lambda: "Unknown", ((v, k) for k, v in entry_kind.items()))
# ilookup = defaultdict(lambda: "PlainText", ((v, k) for k, v in insert_kind.items()))
# return elookup, ilookup
