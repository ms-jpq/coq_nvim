from dataclasses import dataclass
from typing import AbstractSet, Any, Literal, Mapping, Optional, Sequence, Tuple


@dataclass(frozen=True)
class PumDisplay:
    y_max_len: int
    x_max_len: int
    y_ratio: float

    ellipsis: str

    kind_context: Tuple[str, str]
    source_context: Tuple[str, str]


@dataclass(frozen=True)
class PreviewDisplay:
    y_margin: int
    x_margin: int
    x_max_len: int
    lsp_timeout: float


@dataclass(frozen=True)
class Display:
    pum: PumDisplay
    preview: PreviewDisplay
    mark_highlight_group: str


@dataclass(frozen=True)
class Options:
    unifying_chars: AbstractSet[str]
    exact_matches: int
    context_lines: int

    fuzzy_cutoff: float
    timeout: float
    manual_timeout: float


@dataclass(frozen=True)
class Weights:
    consecutive_matches: float
    insertion_order: float
    neighbours: float
    num_matches: float
    prefix_matches: float


@dataclass(frozen=True)
class KeyMapping:
    recommended: bool
    manual_complete: Optional[str]
    jump_to_mark: Optional[str]
    bigger_preview: Optional[str]


@dataclass(frozen=True)
class BaseClient:
    enabled: bool
    short_name: str
    tie_breaker: int


@dataclass(frozen=True)
class WordbankClient(BaseClient):
    match_syms: bool


@dataclass(frozen=True)
class BuffersClient(WordbankClient):
    same_filetype: bool


@dataclass(frozen=True)
class TagsClient(WordbankClient):
    parent_scope: str
    path_sep: str


@dataclass(frozen=True)
class SnippetClient(BaseClient):
    pass


@dataclass(frozen=True)
class Clients:
    buffers: BuffersClient
    lsp: BaseClient
    paths: BaseClient
    snippets: SnippetClient
    tags: TagsClient
    tmux: WordbankClient
    tree_sitter: BaseClient
    tabnine: BaseClient


@dataclass(frozen=True)
class Settings:
    idle_time: float
    display: Display
    match: Options
    weights: Weights
    keymap: KeyMapping
    clients: Clients

