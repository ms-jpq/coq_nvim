from dataclasses import dataclass
from typing import AbstractSet, MutableMapping
from uuid import UUID

from ..databases.buffers.database import BDB
from ..databases.insertions.database import IDB
from ..databases.snippets.database import SDB
from ..databases.tags.database import CTDB
from ..databases.tmux.database import TMDB
from ..databases.treesitter.database import TDB
from ..shared.runtime import Metric, Supervisor, Worker
from ..shared.settings import Settings
from ..shared.types import Completion


@dataclass(frozen=True)
class Stack:
    settings: Settings
    lru: MutableMapping[UUID, Completion]
    metrics: MutableMapping[UUID, Metric]
    bdb: BDB
    idb: IDB
    tdb: TDB
    sdb: SDB
    ctdb: CTDB
    tmdb: TMDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]
