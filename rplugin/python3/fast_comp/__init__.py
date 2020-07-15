from pynvim import Nvim, autocmd, plugin


@plugin
class Main:
    def __init__(self, nvim: Nvim):
        self.nvim = nvim

    @autocmd("TextChangedI")
    def comp1(self) -> None:
        pass

    @autocmd("TextChangedP")
    def comp2(self) -> None:
        pass
