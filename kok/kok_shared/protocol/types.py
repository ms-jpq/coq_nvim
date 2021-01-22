from abc import abstractmethod
from dataclasses import dataclass
from typing import (
    AbstractSet,
    Annotated,
    Literal,
    Optional,
    Protocol,
    Sequence,
    Tuple,
    Union,
    runtime_checkable,
)


@dataclass(frozen=True)
class MatchOptions:
    unifying_chars: Annotated[
        AbstractSet[str], "Alphanumeric chars linked by these chars constitute as words"
    ]


Position = Tuple[int, int]


@dataclass(frozen=True)
class Context:
    """
    |...                            line                            ...|
    |...        line_before           🐭          line_after        ...|
    |...   <syms_before><words_before>🐭<words_after><syms_after>   ...|
    """

    filename: str
    filetype: str

    position: Position

    line: str
    line_before: str
    line_after: str

    line_n: str
    line_before_n: str
    line_after_n: str

    words: str
    words_before: str
    words_after: str

    words_n: str
    words_before_n: str
    words_after_n: str

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

    edit_type: Literal["Contextual"] = "Contextual"


@dataclass(frozen=True)
class RangeEdit(_BaseEdit, HasEditType):
    """
    End exclusve, like LSP
    """

    begin: Position
    end: Position

    edit_type: Literal["Range"] = "Range"


@dataclass(frozen=True)
class SnippetEdit(_BaseEdit, HasEditType):
    grammar: Annotated[str, "ie. LSP, Texmate, Ultisnip, etc"]

    edit_type: Literal["Snippet"] = "Snippet"


@dataclass(frozen=True)
class Completion:
    position: Position
    primary_edit: Union[Edit, ContextualEdit, SnippetEdit, None]
    secondary_edits: Sequence[RangeEdit] = ()
    sortby: str = ""
    label: str = ""
    kind: str = ""
    doc: str = ""
    doc_type: str = ""
