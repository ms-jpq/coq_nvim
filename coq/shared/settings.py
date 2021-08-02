from dataclasses import dataclass
from typing import AbstractSet, Optional, Tuple


@dataclass(frozen=True)
class Limits:
    idle_timeout: float
    index_cutoff: int
    completion_auto_timeout: float
    completion_manual_timeout: float
    download_retries: int
    download_timeout: float


@dataclass(frozen=True)
class PumDisplay:
    y_ratio: float
    y_max_len: int

    x_max_len: int
    x_truncate_len: int

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
    x_max_len: int
    positions: PreviewPositions
    resolve_timeout: float


@dataclass(frozen=True)
class Display:
    pum: PumDisplay
    preview: PreviewDisplay
    mark_highlight_group: str


@dataclass(frozen=True)
class Options:
    unifying_chars: AbstractSet[str]
    max_results: int
    proximate_lines: int
    look_ahead: int
    exact_matches: int
    fuzzy_cutoff: float


@dataclass(frozen=True)
class Weights:
    prefix_matches: float
    edit_distance: float
    recency: float
    proximity: float


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
class PathsClient(BaseClient):
    preview_lines: int




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
    sources: AbstractSet[str]


@dataclass(frozen=True)
class Clients:
    buffers: BuffersClient
    lsp: BaseClient
    paths: PathsClient
    snippets: SnippetClient
    tags: TagsClient
    tmux: WordbankClient
    tree_sitter: BaseClient
    tabnine: BaseClient


@dataclass(frozen=True)
class Settings:
    limits: Limits
    display: Display
    match: Options
    weights: Weights
    keymap: KeyMapping
    clients: Clients
