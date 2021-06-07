from pynvim import Nvim
from pynvim_pp.api import get_cwd


class State:
    def __init__(self, nvim: Nvim) -> None:
        self.insertion_mode = nvim.api.get_mode()["mode"] == "i"
        self.cwd = get_cwd(nvim)
