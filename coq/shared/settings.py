from dataclasses import dataclass
from pathlib import PurePath
from typing import AbstractSet, Any, Literal, Mapping, Optional, Sequence, Tuple


@dataclass(frozen=True)
class PumDisplay:
    y_max_len: int
    x_max_len: int
    y_ratio: float
    x_margin: int

    ellipsis: str

    kind_context: Tuple[str, str]
    source_context: Tuple[str, str]


@dataclass(frozen=True)
class PreviewDisplay:
    margin: int


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
    count_by_filetype: float
    insertion_order: float
    match_density: float
    nearest_neighbour: float
    num_matches: float
    prefix_matches: float


@dataclass(frozen=True)
class KeyMapping:
    recommended: bool
    manual_complete: Optional[str]
    jump_to_mark: Optional[str]


@dataclass(frozen=True)
class BaseClient:
    enabled: bool
    short_name: str
    tie_breaker: int


@dataclass(frozen=True)
class WordbankClient(BaseClient):
    match_syms: bool


@dataclass(frozen=True)
class PollingClient(WordbankClient):
    polling_interval: float


@dataclass(frozen=True)
class LSProtocol:
    CompletionItemKind: Mapping[str, str]
    InsertTextFormat: Mapping[str, str]


@dataclass(frozen=True)
class LSPClient(BaseClient, LSProtocol):
    pass


@dataclass(frozen=True)
class SnippetClient(BaseClient):
    extends: Mapping[str, Mapping[str, Literal[True]]]
    snippets: Mapping[str, Sequence[Any]]


@dataclass(frozen=True)
class TabnineClient(BaseClient):
    bin: Optional[PurePath]


@dataclass(frozen=True)
class Clients:
    buffers: WordbankClient
    lsp: LSPClient
    paths: BaseClient
    snippets: SnippetClient
    tags: PollingClient
    tmux: PollingClient
    tree_sitter: BaseClient
    tabnine: TabnineClient


@dataclass(frozen=True)
class Settings:
    display: Display
    match: Options
    weights: Weights
    keymap: KeyMapping
    clients: Clients

