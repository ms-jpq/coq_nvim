from pynvim import Nvim
from pynvim_pp.api import cur_buf

from ...registry import autocmd, rpc

_SEEN = {0}

@rpc(blocking=True)
def _sub(nvim: Nvim, *_: None) -> None:
    buf = cur_buf(nvim)
    if buf.number in _SEEN:
        pass
    else:
        _SEEN.add(buf.number)
        succ = nvim.api.buf_attach(buf, True, {})
        assert succ


autocmd("BufNew") << f"lua {_sub.name}()"
