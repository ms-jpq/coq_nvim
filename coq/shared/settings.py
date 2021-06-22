from dataclasses import dataclass
from typing import AbstractSet, Any, Literal, Mapping, Optional, Sequence

@dataclass(frozen=True)
class _Pum:
    y_max_len: int
    x_max_len: int
    y_ratio: float
    x_margin: int

@dataclass(frozen=True)
class Display:
    pum: _Pum
    ellipsis: str
    mark_highlight_group: str


@dataclass(frozen=True)
class Options:
    timeout: float
    manual_timeout: float
    transpose_band: int
    unifying_chars: AbstractSet[str]


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
    weight: float


@dataclass(frozen=True)
class WordbankClient(BaseClient):
    match_syms: bool


@dataclass(frozen=True)
class PollingClient(WordbankClient):
    polling_interval: float


@dataclass(frozen=True)
class LSProtocol:
    cmp_item_kind: Mapping[str, str]


@dataclass(frozen=True)
class LSPClient(BaseClient, LSProtocol):
    pass


@dataclass(frozen=True)
class SnippetClient(BaseClient):
    extends: Mapping[str, Mapping[str, Literal[True]]]
    snippets: Mapping[str, Sequence[Any]]


@dataclass(frozen=True)
class Clients:
    buffers: WordbankClient
    lsp: LSPClient
    paths: BaseClient
    snippets: SnippetClient
    tmux: PollingClient
    tree_sitter: BaseClient


@dataclass(frozen=True)
class Settings:
    display: Display
    match: Options
    weights: Weights
    keymap: KeyMapping
    clients: Clients

