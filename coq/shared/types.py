from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path, PurePath
from typing import Any, Literal, Mapping, Optional, Sequence, Tuple, Union
from uuid import UUID, uuid4

UTF8: Literal["UTF-8"] = "UTF-8"
UTF16: Literal["UTF-16-LE"] = "UTF-16-LE"
# TODO: utf-32
UTF32: Literal["UTF-32-LE"] = "UTF-32-LE"
Encoding = Literal["UTF-8", "UTF-16-LE", "UTF-32-LE"]

NvimCursor = int
WTF8Cursor = int

# In nvim, the col is a ut8 byte offset
NvimPos = Tuple[int, NvimCursor]
# Depends on `OffsetEncoding`
WTF8Pos = Tuple[int, WTF8Cursor]

BYTE_TRANS = {
    UTF8: 1,
    UTF16: 2,
    UTF32: 4,
}


@dataclass(frozen=True)
class ChangeEvent:
    range: range
    lines: Sequence[str]


Cursors = Tuple[int, NvimCursor, WTF8Cursor, WTF8Cursor]


@dataclass(frozen=True)
class Context:
    """
    |...                            line                            ...|
    |...        line_before           🐭          line_after        ...|
    |...   <syms_before><words_before>🐭<words_after><syms_after>   ...|
    """

    manual: bool

    # CHANGE ID <-> Triggered by NVIM, ie lines changes
    change_id: UUID
    # COMMIT ID <-> Triggered by COQ
    commit_id: UUID

    cwd: PurePath
    buf_id: int
    filetype: str
    filename: str
    line_count: int
    linefeed: Literal["\r\n", "\n", "\r"]
    tabstop: int
    expandtab: bool
    comment: Tuple[str, str]

    position: NvimPos
    cursor: Cursors
    scr_col: int
    win_size: int

    line: str
    line_before: str
    line_after: str

    lines: Sequence[str]
    lines_before: Sequence[str]
    lines_after: Sequence[str]

    words: str
    words_before: str
    words_after: str

    syms: str
    syms_before: str
    syms_after: str

    ws_before: str
    ws_after: str

    l_words_before: str
    l_words_after: str

    l_syms_before: str
    l_syms_after: str

    is_lower: bool

    change: Optional[ChangeEvent]


@dataclass(frozen=True)
class Edit:
    new_text: str


@dataclass(frozen=True)
class ContextualEdit(Edit):
    """
    <new_prefix>🐭<new_suffix>
    """

    old_prefix: str
    new_prefix: str
    old_suffix: str = ""


@dataclass(frozen=True)
class BaseRangeEdit(Edit):
    """
    End exclusve, like LSP
    """

    begin: WTF8Pos
    end: WTF8Pos
    cursor_pos: WTF8Cursor
    encoding: Encoding


@dataclass(frozen=True)
class RangeEdit(BaseRangeEdit):
    fallback: str


class SnippetGrammar(Enum):
    lit = auto()
    lsp = auto()
    snu = auto()


@dataclass(frozen=True)
class SnippetEdit(Edit):
    grammar: SnippetGrammar


@dataclass(frozen=True)
class SnippetRangeEdit(SnippetEdit, BaseRangeEdit):
    fallback: Optional[str]


@dataclass(frozen=True)
class Mark:
    idx: int
    begin: NvimPos
    end: NvimPos
    text: str


@dataclass(frozen=True)
class Doc:
    text: str
    syntax: str


@dataclass(frozen=True)
class ExternLSP:
    client: Optional[str]
    item: Mapping
    command: Optional[Any]


@dataclass(frozen=True)
class ExternLUA(ExternLSP):
    ...


@dataclass(frozen=True)
class ExternPath:
    is_dir: bool
    path: Path


@dataclass(frozen=True)
class Completion:
    source: str
    always_on_top: bool
    weight_adjust: float
    label: str
    sort_by: str
    primary_edit: Edit
    adjust_indent: bool
    icon_match: Optional[str]

    uid: UUID = field(default_factory=uuid4)
    secondary_edits: Sequence[RangeEdit] = ()
    preselect: bool = False
    kind: str = ""
    doc: Optional[Doc] = None
    extern: Union[ExternLSP, ExternLUA, ExternPath, None] = None
