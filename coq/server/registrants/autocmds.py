from asyncio import Handle, get_running_loop
from itertools import chain
from typing import MutableSet, Optional, Sequence

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_filetype, cur_buf, list_bufs
from pynvim_pp.lib import async_call, go
from std2.pickle import new_decoder

from ...registry import atomic, autocmd, rpc
from ...snippets.types import ParsedSnippet
from ..rt_types import Stack

_SEEN: MutableSet[str] = set()

_DECODER = new_decoder(Sequence[ParsedSnippet])


@rpc(blocking=True)
def _ft_changed(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    ft = buf_filetype(nvim, buf=buf)

    stack.bdb.ft_update(buf.number, filetype=ft)

    if ft not in _SEEN:
        _SEEN.add(ft)
        snippets = stack.settings.clients.snippets
        mappings = {
            f: _DECODER(snippets.snippets.get(f, ()))
            for f in chain(snippets.extends.get(ft, {}).keys(), (ft,))
        }
        stack.sdb.populate(mappings)


autocmd("FileType") << f"lua {_ft_changed.name}()"
atomic.exec_lua(f"{_ft_changed.name}()", ())


_HANDLE: Optional[Handle] = None


@rpc(blocking=True)
def _when_idle(nvim: Nvim, stack: Stack) -> None:
    global _HANDLE
    if _HANDLE:
        _HANDLE.cancel()

    def cont() -> None:
        bufs = list_bufs(nvim, listed=False)
        stack.bdb.vacuum({buf.number for buf in bufs})
        stack.supervisor.notify_idle()

    get_running_loop().call_later(
        stack.settings.idle_time, lambda: go(async_call(nvim, cont))
    )


autocmd("CursorHold", "CursorHoldI") << f"lua {_when_idle.name}()"

