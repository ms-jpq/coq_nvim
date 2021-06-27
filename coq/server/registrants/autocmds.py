from itertools import chain
from typing import MutableSet, Sequence

from pynvim.api.nvim import Nvim
from pynvim_pp.api import buf_filetype, buf_name, cur_buf
from std2.pickle import decode

from ...registry import atomic, autocmd, rpc
from ...snippets.types import ParsedSnippet
from ..runtime import Stack

_SEEN: MutableSet[str] = set()


@rpc(blocking=True)
def _ft_changed(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    name = buf_name(nvim, buf=buf)
    ft = buf_filetype(nvim, buf=buf)

    stack.bdb.ft_update(name, filetype=ft)

    if ft not in _SEEN:
        _SEEN.add(ft)
        snippets = stack.settings.clients.snippets
        mappings = {
            f: decode(Sequence[ParsedSnippet], snippets.snippets.get(f, ()))
            for f in chain(snippets.extends.get(ft, {}).keys(), (ft,))
        }
        stack.sdb.populate(mappings)


autocmd("FileType") << f"lua {_ft_changed.name}()"
atomic.exec_lua(f"{_ft_changed.name}()", ())

