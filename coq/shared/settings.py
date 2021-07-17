from dataclasses import dataclass
from typing import AbstractSet, Optional, Tuple


@dataclass(frozen=True)
class Limits:
    idle_time: float
    max_buf_index: int
    timeout: float
    manual_timeout: float


@dataclass(frozen=True)
class PumDisplay:
    y_ratio: float
    y_max_len: int

    x_max_len: int
    x_min_len: int

    ellipsis: str

    kind_context: Tuple[str, str]
    source_context: Tuple[str, str]


@dataclass(frozen=True)
class PreviewPositions:
    north: Optional[int]
    south: Optional[int]
    west: Optional[int]
    east: Optional[int]


@dataclass(frozen=True)
class PreviewDisplay:
    y_margin: int
    x_margin: int
    x_max_len: int
    positions: PreviewPositions
    lsp_timeout: float


@dataclass(frozen=True)
class Display:
    pum: PumDisplay
    preview: PreviewDisplay
    mark_highlight_group: str


@dataclass(frozen=True)
class Options:
    max_results: int
    unifying_chars: AbstractSet[str]
    exact_matches: int
    context_lines: int

    fuzzy_cutoff: float


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
class TabnineClient(BaseClient):
    download_retries: int
    download_timeout: float


@dataclass(frozen=True)
class Clients:
    buffers: BuffersClient
    lsp: BaseClient
    paths: BaseClient
    snippets: SnippetClient
    tags: TagsClient
    tmux: WordbankClient
    tree_sitter: BaseClient
    tabnine: TabnineClient


@dataclass(frozen=True)
class Settings:
    limits: Limits
    display: Display
    match: Options
    weights: Weights
    keymap: KeyMapping
    clients: Clients

