from dataclasses import dataclass

from pynvim import Nvim
from pynvim_pp.api import get_cwd


@dataclass
class State:
    insertion_mode: bool
    cwd: str


def new_state(nvim: Nvim) -> State:
    state = State(insertion_mode=nvim.api.get_mode()["mode"] == "i", cwd=get_cwd(nvim))
    return state
