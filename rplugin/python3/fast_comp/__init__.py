from pynvim import Nvim, plugin


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim
