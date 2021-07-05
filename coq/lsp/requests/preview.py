from dataclasses import asdict
from pathlib import Path
from typing import Optional

from pynvim import Nvim
from pynvim_pp.logging import log
from std2.pickle import DecodeError, new_decoder

from ...registry import atomic
from ...shared.types import Doc
from ..parse import doc
from ..types import CompletionItem
from .request import blocking_request

_LUA = (Path(__file__).resolve().parent / "preview.lua").read_text("UTF-8")

atomic.exec_lua(_LUA, ())

_DECODER = new_decoder(CompletionItem, strict=False)


def request(nvim: Nvim, item: CompletionItem) -> Optional[Doc]:
    stream = blocking_request(nvim, "COQlsp_preview", item)
    for reply in stream:
        if reply:
            break
    else:
        reply = None

    try:
        resp: CompletionItem = _DECODER(reply)
    except DecodeError as e:
        log.warn("%s", e)
        return None
    else:
        return doc(resp)

