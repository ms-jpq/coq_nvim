from dataclasses import dataclass
from typing import Annotated, FrozenSet, Literal, Optional, Protocol, Sequence, Union


@dataclass(frozen=True)
class MatchOptions:
    unifying_chars: Annotated[
        FrozenSet[str], "Alphanumeric chars linked by these chars constitute as words"
    ]


@dataclass(frozen=True)
class Position:
    """
    0 based Index
    """

    row: int
    col: int


@dataclass(frozen=True)
class Context:
    """
    |...                            line                            ...|
    |...        line_before           🐭          line_after        ...|
    |...   <syms_before><words_before>🐭<words_after><syms_after>   ...|
    """

    uid: int

    filename: str
    filetype: str

    position: Position

    line: str
    line_normalized: str
    line_before: str
    line_before_normalized: str
    line_after: str
    line_after_normalized: str

    words: str
    words_normalized: str
    words_before: str
    words_before_normalized: str
    words_after: str
    words_after_normalized: str

    syms: str
    syms_before: str
    syms_after: str

    words_syms: str
    words_syms_normalized: str
    words_syms_before: str
    words_syms_before_normalized: str
    words_syms_after: str
    words_syms_after_normalized: str


class HasEditType(Protocol):
    @property
    def edit_type(self) -> str:
        ...


@dataclass(frozen=True)
class _BaseEdit:
    new_text: str


@dataclass(frozen=True)
class Edit(_BaseEdit, HasEditType):
    edit_type: Literal["Edit"] = "Edit"


@dataclass(frozen=True)
class ContextualEdit(_BaseEdit, HasEditType):
    """
    <new_prefix>🐭<new_suffix>
    """

    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str

    edit_type: Literal["ContextualEdit"] = "ContextualEdit"


@dataclass(frozen=True)
class RangeEdit(_BaseEdit, HasEditType):
    """
    End exclusve, like LSP
    """

    begin: Position
    end: Position

    edit_type: Literal["RangeEdit"] = "RangeEdit"


@dataclass(frozen=True)
class Snippet(_BaseEdit, HasEditType):
    grammar: Annotated[str, "ie. LSP, Texmate, Ultisnip, etc"]

    edit_type: Literal["Snippet"] = "Snippet"


@dataclass(frozen=True)
class Completion:
    position: Position
    primary_edit: Union[Edit, ContextualEdit, Snippet, None]
    secondary_edits: Sequence[RangeEdit] = ()
    label: Optional[str] = None
    sortby: Optional[str] = None
    kind: Optional[str] = None
    doc: Optional[str] = None
