from dataclasses import dataclass
from typing import AbstractSet, Any, Literal, Mapping, Optional, Sequence


@dataclass(frozen=True)
class Display:
    ellipsis: str
    pum_max_len: int


@dataclass(frozen=True)
class Options:
    timeout: float
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
    prev_mark: str
    next_mark: str


@dataclass(frozen=True)
class BaseClient:
    enabled: bool
    short_name: str
    weight: float


@dataclass(frozen=True)
class PollingClient(BaseClient):
    polling_interval: float


@dataclass(frozen=True)
class LSPClient(BaseClient):
    cmp_item_kind: Mapping[Optional[int], str]


@dataclass(frozen=True)
class SnippetClient(BaseClient):
    extends: Mapping[str, Mapping[str, Literal[True]]]
    snippets: Mapping[str, Sequence[Any]]


@dataclass(frozen=True)
class Clients:
    buffers: BaseClient
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

