from itertools import chain
from threading import Timer
from typing import MutableSet, Sequence

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_filetype, cur_buf, list_bufs
from std2.pickle import new_decoder

from ...registry import atomic, autocmd, enqueue_event, rpc
from ...shared.timeit import timeit
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


_TIMER = Timer(0, lambda: None)


@rpc(blocking=False)
def _on_idle(nvim: Nvim, stack: Stack) -> None:
    with timeit("IDLE"):
        bufs = list_bufs(nvim, listed=False)
        stack.bdb.vacuum({buf.number for buf in bufs})


@rpc(blocking=False)
def _when_idle(nvim: Nvim, stack: Stack) -> None:
    global _TIMER
    _TIMER.cancel()
    _TIMER = Timer(1, lambda: enqueue_event(_on_idle))
    _TIMER.start()


autocmd("CursorHold", "CursorHoldI") << f"lua {_when_idle.name}()"

