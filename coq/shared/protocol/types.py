from abc import abstractmethod
from dataclasses import dataclass
from enum import Enum, auto
from typing import (
    Annotated,
    Literal,
    Protocol,
    Sequence,
    Tuple,
    Union,
    runtime_checkable,
)


class OffsetEncoding(Enum):
    utf_8 = auto()  # equivalent to NvimPos
    utf_16 = auto()  # LSP


NvimPos = Tuple[int, Annotated[int, "In nvim, the col is a ut8 byte offset"]]
WTF8Pos = Tuple[int, Annotated[int, "Depends on `OffsetEncoding`"]]


@dataclass(frozen=True)
class Context:
    """
    |...                            line                            ...|
    |...        line_before           🐭          line_after        ...|
    |...   <syms_before><words_before>🐭<words_after><syms_after>   ...|
    """

    project: str
    filename: str
    filetype: str

    position: NvimPos

    line: str
    line_before: str
    line_after: str

    words: str
    words_before: str
    words_after: str

    syms: str
    syms_before: str
    syms_after: str


@runtime_checkable
class HasEditType(Protocol):
    @property
    @abstractmethod
    def edit_type(self) -> str:
        ...


@dataclass(frozen=True)
class _BaseEdit:
    new_text: str


@dataclass(frozen=True)
class Edit(_BaseEdit, HasEditType):
    edit_type: Literal["Vanilla"] = "Vanilla"


@dataclass(frozen=True)
class ContextualEdit(_BaseEdit, HasEditType):
    """
    <new_prefix>🐭<new_suffix>
    """

    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str


@dataclass(frozen=True)
class RangeEdit(_BaseEdit, HasEditType):
    """
    End exclusve, like LSP
    """

    begin: WTF8Pos
    end: WTF8Pos


@dataclass(frozen=True)
class SnippetEdit(_BaseEdit, HasEditType):
    grammar: Annotated[str, "ie. LSP, Texmate, Ultisnip, etc"]

    edit_type: Literal["Snippet"] = "Snippet"


ApplicableEdit = Union[Edit, RangeEdit, ContextualEdit]


@dataclass(frozen=True)
class Completion:
    position: NvimPos
    encoding: OffsetEncoding
    primary_edit: Union[ApplicableEdit, SnippetEdit]
    secondary_edits: Sequence[RangeEdit] = ()
    label: str = ""
    short_label: str = ""
    doc: str = ""
    doc_type: str = ""


@dataclass(frozen=True)
class SnippetContext:
    snippet: SnippetEdit
    expand_tabs: bool
    tab_size: bool
