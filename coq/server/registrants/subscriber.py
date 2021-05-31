from pynvim import Nvim
from pynvim_pp.api import buf_get_option, cur_buf

from ...registry import autocmd, rpc

_SEEN = {0}


@rpc(blocking=True)
def _sub(nvim: Nvim, *_: None) -> None:
    buf = cur_buf(nvim)
    if buf.number in _SEEN:
        pass
    else:
        _SEEN.add(buf.number)
        listed = buf_get_option(nvim, buf=buf, key="buflisted")
        if listed:
            succ = nvim.api.buf_attach(buf, True, {})
            assert succ


autocmd("BufNew") << f"lua {_sub.name}()"
