from pynvim import Nvim
from pynvim_pp.client import BasicClient
from pynvim_pp.lib import async_call, write


class Client(BasicClient):
    def wait(self, nvim: Nvim) -> int:
        return super().wait(nvim)
