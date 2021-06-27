from dataclasses import dataclass, field
from typing import Annotated, Literal, Optional, Sequence, Tuple, Union
from uuid import UUID, uuid4

UTF8 = "UTF-8"
UTF16 = "UTF-16-LE"

NvimPos = Tuple[int, Annotated[int, "In nvim, the col is a ut8 byte offset"]]
WTF8Pos = Tuple[int, Annotated[int, "Depends on `OffsetEncoding`"]]

BYTE_TRANS = {
    UTF8: 1,
    UTF16: 2,
}


@dataclass(frozen=True)
class Context:
    """
    |...                            line                            ...|
    |...        line_before           🐭          line_after        ...|
    |...   <syms_before><words_before>🐭<words_after><syms_after>   ...|
    """

    uid: UUID
    changedtick: int

    cwd: str
    filetype: str
    filename: str
    line_count: int
    linefeed: Literal["\r\n", "\n", "\r"]
    tabstop: int
    expandtab: bool
    comment: Tuple[str, str]

    position: NvimPos

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
class RangeEdit(Edit):
    """
    End exclusve, like LSP
    """

    begin: WTF8Pos
    end: WTF8Pos
    encoding: str = UTF16


@dataclass(frozen=True)
class SnippetEdit(Edit):
    grammar: Annotated[str, "ie. LSP, Texmate, Ultisnip, etc"]


@dataclass(frozen=True)
class Mark:
    idx: int
    begin: NvimPos
    end: NvimPos


ApplicableEdit = Union[Edit, RangeEdit, ContextualEdit]
PrimaryEdit = Union[ApplicableEdit, SnippetEdit]


@dataclass(frozen=True)
class Doc:
    text: str
    filetype: str


@dataclass(frozen=True)
class Completion:
    source: str
    tie_breaker: int
    label: str
    primary_edit: PrimaryEdit
    secondary_edits: Sequence[RangeEdit] = ()
    sort_by: str = ""
    kind: str = ""
    doc: Optional[Doc] = None
    uid: UUID = field(default_factory=uuid4)

