from dataclasses import dataclass
from typing import AbstractSet, MutableMapping
from uuid import UUID

from ..databases.buffers.database import BDB
from ..databases.insertions.database import IDB
from ..databases.snippets.database import SDB
from ..shared.runtime import Metric, Supervisor, Worker
from ..shared.settings import Settings
from ..shared.types import Completion


class ValidationError(Exception):
    ...


@dataclass(frozen=True)
class Stack:
    settings: Settings
    lru: MutableMapping[UUID, Completion]
    metrics: MutableMapping[UUID, Metric]
    bdb: BDB
    idb: IDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]
