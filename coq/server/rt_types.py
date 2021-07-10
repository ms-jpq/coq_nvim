from dataclasses import dataclass
from typing import AbstractSet

from ..databases.buffers.database import BDB
from ..databases.insertions.database import IDB
from ..databases.snippets.database import SDB
from ..shared.runtime import Supervisor, Worker
from ..shared.settings import Settings


@dataclass(frozen=True)
class Stack:
    settings: Settings
    bdb: BDB
    sdb: SDB
    idb: IDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]

