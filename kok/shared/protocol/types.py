from abc import abstractmethod
from dataclasses import dataclass
from typing import (
    AbstractSet,
    Annotated,
    Literal,
    Protocol,
    Sequence,
    Tuple,
    Union,
    runtime_checkable,
)


@dataclass(frozen=True)
class Options:
    unifying_chars: Annotated[
        AbstractSet[str], "Alphanumeric chars linked by these chars constitute as words"
    ]


NvimPos = Annotated[
    Tuple[int, Annotated[int, "In nvim, the col is a ut8 byte offset"]], "0,0 based"
]


@dataclass(frozen=True)
class WTF8Pos:
    """
    0,0 based
    """

    row: int
    col: int
    encoding: Literal["UTF-8", "UTF-16"]


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

    position: WTF8Pos

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
class RangeEdit(_BaseEdit, HasEditType):
    """
    End exclusve, like LSP
    """

    begin: WTF8Pos
    end: WTF8Pos


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
class SnippetEdit(_BaseEdit, HasEditType):
    grammar: Annotated[str, "ie. LSP, Texmate, Ultisnip, etc"]

    edit_type: Literal["Snippet"] = "Snippet"


ApplicableEdit = Union[Edit, RangeEdit, ContextualEdit]


@dataclass(frozen=True)
class Completion:
    position: WTF8Pos
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
