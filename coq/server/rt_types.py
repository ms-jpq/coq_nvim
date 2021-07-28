from dataclasses import dataclass
from typing import AbstractSet

from ..databases.buffers.database import BDB
from ..databases.insertions.database import IDB
from ..databases.snippets.database import SDB
from ..databases.tags.database import CTDB
from ..databases.tmux.database import TMDB
from ..databases.treesitter.database import TDB
from ..shared.runtime import Supervisor, Worker
from ..shared.settings import Settings


@dataclass(frozen=True)
class Stack:
    settings: Settings
    bdb: BDB
    idb: IDB
    tdb: TDB
    sdb: SDB
    ctdb: CTDB
    tmdb: TMDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]
