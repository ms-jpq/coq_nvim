from dataclasses import asdict
from pathlib import Path

from pynvim import Nvim

from ...registry import atomic
from .request import blocking_request

_LUA = (Path(__file__).resolve().parent / "preview.lua").read_text("UTF-8")

atomic.exec_lua(_LUA, ())


def request(nvim: Nvim) -> None:
    # reply = blocking_request(nvim, "COQlsp_comp", str(session), (row, col))

    pass
