from dataclasses import dataclass

from pynvim import Nvim
from pynvim_pp.api import get_cwd
from std2.configparser import hydrate
from std2.pickle import decode
from std2.tree import merge
from yaml import safe_load

from ..consts import CONFIG_YML, SETTINGS_VAR
from ..shared.settings import Settings


def _settings(nvim: Nvim) -> Settings:
    user_config = nvim.vars.get(SETTINGS_VAR, {})
    config: Settings = decode(
        Settings,
        merge(
            safe_load(CONFIG_YML.read_text("UTF-8")), hydrate(user_config), replace=True
        ),
    )
    return config


@dataclass
class State:
    settings: Settings
    inserting: bool
    cwd: str


def new_state(nvim: Nvim) -> State:
    state = State(
        settings=_settings(nvim),
        inserting=nvim.api.get_mode()["mode"] == "i",
        cwd=get_cwd(nvim),
    )
    return state
