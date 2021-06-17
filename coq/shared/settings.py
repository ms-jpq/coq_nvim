from dataclasses import dataclass
from typing import AbstractSet, Any, Mapping


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
    alphabetical: float
    consecutive_matches: float
    count_by_filetype: float
    insertion_order: float
    match_density: float
    nearest_neighbour: float
    num_matches: float
    prefix_matches: float


@dataclass(frozen=True)
class BaseClient:
    short_name: str
    weight: float


@dataclass(frozen=True)
class PollingClient(BaseClient):
    polling_interval: float


@dataclass(frozen=True)
class Clients:
    buffers: BaseClient
    lsp: BaseClient
    paths: BaseClient
    tmux: PollingClient
    tree_sitter: BaseClient


@dataclass(frozen=True)
class Settings:
    display: Display
    match: Options
    weights: Weights
    clients: Clients

