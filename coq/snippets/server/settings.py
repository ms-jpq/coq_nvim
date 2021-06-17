from pynvim import Nvim

from ..shared.nvim import call
from .types import InstanceSettings


async def instance(nvim: Nvim) -> InstanceSettings:
    def cont() -> InstanceSettings:
        prefer_tabs = not nvim.api.get_option("expandtab")
        tab_width = nvim.api.get_option("tabstop")
        settings = InstanceSettings(prefer_tabs=prefer_tabs, tab_width=tab_width)
        return settings

    return await call(nvim, cont)
