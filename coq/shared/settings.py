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
    nearest_neighbour: float
    num_matches: float
    prefix_matches: float


@dataclass(frozen=True)
class _BaseClient:
    short_name: str
    weight: float


@dataclass(frozen=True)
class BasicClient(_BaseClient):
    prefix_length: int


@dataclass(frozen=True)
class Clients:
    buffers: BasicClient
    lsp: _BaseClient
    paths: _BaseClient
    tmux: BasicClient
    tree_sitter: _BaseClient


@dataclass(frozen=True)
class Settings:
    display: Display
    match: Options
    weights: Weights
    clients: Clients

