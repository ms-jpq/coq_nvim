from dataclasses import dataclass
from typing import Any, Mapping

from pynvim import Nvim
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, rpc
from ...shared.nvim.completions import VimCompletion
from ...shared.timeit import timeit
from ...shared.types import Doc
from ..runtime import Stack
from ..types import UserData


@dataclass(frozen=True)
class _Event:
    completed_item: VimCompletion[UserData]
    height: int
    width: int
    row: int
    col: int
    size: int
    scrollbar: bool


def _preview(nvim: Nvim, event: _Event, doc: Doc) -> None:
    pass


@rpc(blocking=True)
def _cmp_changed(nvim: Nvim, stack: Stack, event: Mapping[str, Any] = {}) -> None:
    with timeit(0, "PREVIEW"):
        try:
            ev: _Event = decode(_Event, event, decoders=BUILTIN_DECODERS)
        except DecodeError:
            pass
        else:
            if (
                ev.completed_item.user_data
                and ev.completed_item.user_data.doc
                and ev.completed_item.user_data.doc.text
            ):
                _preview(nvim, event=ev, doc=ev.completed_item.user_data.doc)


autocmd("CompleteChanged") << f"lua {_cmp_changed.name}(vim.v.event)"

