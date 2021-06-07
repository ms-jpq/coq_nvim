from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from hashlib import md5

from pynvim import Nvim
from pynvim_pp.api import get_cwd
from std2.configparser import hydrate
from std2.pickle import decode
from std2.tree import merge
from yaml import safe_load

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
    print(location, flush=True)
    db = Database(location=str(location))
    return db


def stack(pool: ThreadPoolExecutor, nvim: Nvim) -> Stack:
    settings = _settings(nvim)
    cwd = get_cwd(nvim)
    state = _State(
        inserting=nvim.api.get_mode()["mode"] == "i",
        cwd=cwd,
    )
    supervisor = Supervisor(pool=pool, nvim=nvim, options=settings.match)
    stack = Stack(
        settings=settings,
        state=state,
        db=_db(cwd),
        supervisor=supervisor,
    )
    return stack
