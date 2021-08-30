from concurrent.futures import Executor
from pathlib import Path, PurePath
from typing import Iterator

from pynvim import Nvim
from pynvim_pp.api import get_cwd
from std2.configparser import hydrate
from std2.pickle import new_decoder
from std2.tree import merge
from yaml import safe_load

from ..clients.buffers.worker import Worker as BuffersWorker
from ..clients.lsp.worker import Worker as LspWorker
from ..clients.paths.worker import Worker as PathsWorker
from ..clients.snippet.worker import Worker as SnippetWorker
from ..clients.t9.worker import Worker as T9Worker
from ..clients.tags.worker import Worker as TagsWorker
from ..clients.tmux.worker import Worker as TmuxWorker
from ..clients.tree_sitter.worker import Worker as TreeWorker
from ..consts import CONFIG_YML, SETTINGS_VAR, VARS
from ..databases.buffers.database import BDB
from ..databases.insertions.database import IDB
from ..databases.snippets.database import SDB
from ..databases.tags.database import CTDB
from ..databases.tmux.database import TMDB
from ..databases.treesitter.database import TDB
from ..shared.lru import LRU
from ..shared.runtime import Supervisor, Worker
from ..shared.settings import Settings
from .reviewer import Reviewer
from .rt_types import Stack
from .state import state

_DECODER = new_decoder(Settings)


def _settings(nvim: Nvim) -> Settings:
    user_config = nvim.vars.get(SETTINGS_VAR, {})
    merged = merge(
        safe_load(CONFIG_YML.read_text("UTF-8")),
        hydrate(user_config),
        replace=True,
    )

    config: Settings = _DECODER(merged)
    return config


def _from_each_according_to_their_ability(
    settings: Settings,
    bdb: BDB,
    sdb: SDB,
    tdb: TDB,
    ctdb: CTDB,
    tmdb: TMDB,
    supervisor: Supervisor,
) -> Iterator[Worker]:
    clients = settings.clients

    if clients.buffers.enabled:
        yield BuffersWorker(supervisor, options=clients.buffers, misc=bdb)

    if clients.paths.enabled:
        yield PathsWorker(supervisor, options=clients.paths, misc=None)

    if clients.tree_sitter.enabled:
        yield TreeWorker(supervisor, options=clients.tree_sitter, misc=tdb)

    if clients.lsp.enabled:
        yield LspWorker(supervisor, options=clients.lsp, misc=None)

    if clients.snippets.enabled:
        yield SnippetWorker(supervisor, options=clients.snippets, misc=sdb)

    if clients.tags.enabled:
        yield TagsWorker(supervisor, options=clients.tags, misc=ctdb)

    if clients.tmux.enabled:
        yield TmuxWorker(supervisor, options=clients.tmux, misc=tmdb)

    if clients.tabnine.enabled:
        yield T9Worker(supervisor, options=clients.tabnine, misc=None)


def stack(pool: Executor, nvim: Nvim) -> Stack:
    settings = _settings(nvim)
    s = state(cwd=PurePath(get_cwd(nvim)))
    bdb, sdb, idb, tdb, ctdb, tmdb = (
        BDB(pool),
        SDB(pool),
        IDB(pool),
        TDB(pool),
        CTDB(pool, cwd=s.cwd),
        TMDB(pool),
    )
    reviewer = Reviewer(
        options=settings.match,
        db=idb,
    )
    supervisor = Supervisor(
        pool=pool,
        nvim=nvim,
        vars_dir=Path(nvim.api.stdpath("cache")) if settings.xdg else VARS,
        options=settings.match,
        limits=settings.limits,
        reviewer=reviewer,
    )
    workers = {
        *_from_each_according_to_their_ability(
            settings,
            bdb=bdb,
            sdb=sdb,
            tdb=tdb,
            ctdb=ctdb,
            tmdb=tmdb,
            supervisor=supervisor,
        )
    }
    stack = Stack(
        settings=settings,
        lru=LRU(size=settings.match.max_results),
        bdb=bdb,
        sdb=sdb,
        idb=idb,
        tdb=tdb,
        ctdb=ctdb,
        tmdb=tmdb,
        supervisor=supervisor,
        workers=workers,
    )
    return stack
