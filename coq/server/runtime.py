from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from hashlib import md5

from pynvim import Nvim
from pynvim_pp.api import get_cwd
from std2.configparser import hydrate
from std2.pickle import decode
from std2.tree import merge
from yaml import safe_load

from ..clients.lsp.worker import Worker as LSPWorker
from ..clients.paths.worker import Worker as PathsWorker
from ..clients.tmux.worker import Worker as TmuxWorker
from ..clients.tree_sitter.worker import Worker as TreeWorker
from ..consts import CONFIG_YML, DB_DIR, SETTINGS_VAR
from ..shared.runtime import Supervisor
from ..shared.settings import Settings
from .model.database import Database


@dataclass
class _State:
    inserting: bool
    cwd: str


@dataclass(frozen=True)
class Stack:
    settings: Settings
    state: _State
    db: Database
    supervisor: Supervisor


def _settings(nvim: Nvim) -> Settings:
    user_config = nvim.vars.get(SETTINGS_VAR, {})
    config: Settings = decode(
        Settings,
        merge(
            safe_load(CONFIG_YML.read_text("UTF-8")), hydrate(user_config), replace=True
        ),
    )
    return config


def _db(cwd: str) -> Database:
    DB_DIR.mkdir(parents=True, exist_ok=True)
    hashed = md5(cwd.encode()).hexdigest()
    location = (DB_DIR / hashed).with_suffix(".sqlite3")
    db = Database(location=str(location))
    return db


def _from_each_according_to_their_ability(db: Database, supervisor: Supervisor) -> None:
    pass


def stack(pool: ThreadPoolExecutor, nvim: Nvim) -> Stack:
    settings = _settings(nvim)
    cwd = get_cwd(nvim)
    state = _State(
        inserting=nvim.api.get_mode()["mode"] == "i",
        cwd=cwd,
    )
    db = _db(cwd)
    supervisor = Supervisor(pool=pool, nvim=nvim, options=settings.match)
    _from_each_according_to_their_ability(db, supervisor=supervisor)
    stack = Stack(
        settings=settings,
        state=state,
        db=db,
        supervisor=supervisor,
    )
    return stack
