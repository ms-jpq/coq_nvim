from dataclasses import dataclass
from threading import Lock
from typing import AbstractSet, Optional, Tuple
from uuid import UUID

from ..shared.runtime import Supervisor, Worker
from ..shared.settings import Settings
from ..shared.types import Context, NvimPos
from .databases.buffers.database import BDB
from .databases.snippets.database import SDB


@dataclass
class _State:
    screen: Tuple[int, int]
    commit: UUID
    cur: Optional[Context]
    request: Optional[NvimPos]
    inserted: Optional[NvimPos]


@dataclass(frozen=True)
class Stack:
    lock: Lock
    settings: Settings
    state: _State
    bdb: BDB
    sdb: SDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]

