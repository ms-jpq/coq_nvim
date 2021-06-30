from dataclasses import dataclass
from typing import AbstractSet

from ..shared.runtime import Supervisor, Worker
from ..shared.settings import Settings
from .databases.buffers.database import BDB
from .databases.snippets.database import SDB


@dataclass(frozen=True)
class Stack:
    settings: Settings
    bdb: BDB
    sdb: SDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]

