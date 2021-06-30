from dataclasses import dataclass
from threading import Lock
from typing import AbstractSet, Optional
from uuid import  uuid4

from ..shared.runtime import Supervisor, Worker
from ..shared.settings import Settings
from ..shared.types import Context, NvimPos
from .databases.buffers.database import BDB
from .databases.snippets.database import SDB


class State:
    def __init__(self) -> None:
        self.lock = Lock()
        self.screen = 0, 0
        self.commit = uuid4()
        self.cur: Optional[Context] = None
        self.request: Optional[NvimPos] = None
        self.inserted: Optional[NvimPos] = None


@dataclass(frozen=True)
class Stack:
    settings: Settings
    state: State
    bdb: BDB
    sdb: SDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]

