from os.path import normcase
from pathlib import Path

from pynvim.api.nvim import Nvim

from ...lang import LANG
from ...registry import atomic, rpc
from ...snippets.types import LoadedSnips
from ..rt_types import Stack


@rpc(blocking=True)
def _load_snips(nvim: Nvim, stack: Stack) -> None:
    pass


atomic.exec_lua(f"{_load_snips.name}()", ())
