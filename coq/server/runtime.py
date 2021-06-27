from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from json import loads
from os import linesep
from typing import AbstractSet, Iterator, Literal, Optional, Sequence, cast
from uuid import UUID, uuid4

from pynvim import Nvim
from pynvim_pp.api import get_cwd
from std2.configparser import hydrate
from std2.pickle import decode
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
from ..consts import CONFIG_YML, LSP_ARTIFACTS, SETTINGS_VAR, SNIPPET_ARTIFACTS
from ..shared.runtime import Supervisor, Worker
from ..shared.settings import Settings
from ..shared.types import Context, EditEnv, NvimPos
from .model.buffers.database import BDB
from .model.snippets.database import SDB


@dataclass
class _State:
    futs: Sequence[Future]
    commit: UUID
    env: EditEnv
    cur: Optional[Context]
    request: bool
    inserted: Optional[NvimPos]
    cwd: str


@dataclass(frozen=True)
class Stack:
    settings: Settings
    state: _State
    bdb: BDB
    sdb: SDB
    supervisor: Supervisor
    workers: AbstractSet[Worker]


def _settings(nvim: Nvim) -> Settings:
    user_config = nvim.vars.get(SETTINGS_VAR, {})
    config: Settings = decode(
        Settings,
        merge(
            safe_load(CONFIG_YML.read_text("UTF-8")),
            {
                "clients": {
                    "lsp": loads(LSP_ARTIFACTS.read_text("UTF-8")),
                    "snippets": loads(SNIPPET_ARTIFACTS.read_text("UTF-8")),
                }
            },
            hydrate(user_config),
            replace=True,
        ),
    )
    return config


def _from_each_according_to_their_ability(
    settings: Settings, bdb: BDB, sdb: SDB, supervisor: Supervisor
) -> Iterator[Worker]:
    clients = settings.clients

    if clients.buffers.enabled:
        yield BuffersWorker(supervisor, options=clients.buffers, misc=bdb)

    if clients.paths.enabled:
        yield PathsWorker(supervisor, options=clients.paths, misc=None)

    if clients.tree_sitter.enabled:
        yield TreeWorker(supervisor, options=clients.tree_sitter, misc=None)

    if clients.lsp.enabled:
        yield LspWorker(supervisor, options=clients.lsp, misc=None)

    if clients.snippets.enabled:
        yield SnippetWorker(supervisor, options=clients.snippets, misc=sdb)

    if clients.tags.enabled:
        yield TagsWorker(supervisor, options=clients.tags, misc=None)

    if clients.tmux.enabled:
        yield TmuxWorker(supervisor, options=clients.tmux, misc=None)

    if clients.tabnine.enabled:
        yield T9Worker(supervisor, options=clients.tabnine, misc=None)


def stack(pool: ThreadPoolExecutor, nvim: Nvim) -> Stack:
    settings = _settings(nvim)
    cwd = get_cwd(nvim)
    env = EditEnv(
        linefeed=cast(Literal["\n"], linesep),
        tabstop=4,
        expandtab=True,
    )
    state = _State(
        commit=uuid4(),
        futs=(),
        env=env,
        cur=None,
        request=False,
        inserted=None,
        cwd=cwd,
    )
    bdb, sdb = BDB(), SDB()
    supervisor = Supervisor(pool=pool, nvim=nvim, options=settings.match)
    workers = {
        *_from_each_according_to_their_ability(
            settings, bdb=bdb, sdb=sdb, supervisor=supervisor
        )
    }
    stack = Stack(
        settings=settings,
        state=state,
        bdb=bdb,
        sdb=sdb,
        supervisor=supervisor,
        workers=workers,
    )
    return stack

