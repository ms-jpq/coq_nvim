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
class State:
    screen: Tuple[int, int]
    commit: UUID
    cur: Optional[Context]
    request: Optional[NvimPos]
    inserted: Optional[NvimPos]


@dataclass(frozen=True)
class Stack:
    lock: Lock
    settings: Settings
    state: State
    bdb: BDB
    sdb: SDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]

