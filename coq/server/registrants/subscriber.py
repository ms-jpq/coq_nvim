from pynvim import Nvim
from pynvim_pp.api import cur_buf

from ...registry import autocmd, rpc


@rpc(blocking=True)
def _sub(nvim: Nvim, *_: None) -> None:
    # buf = cur_buf(nvim)
    succ = nvim.api.buf_attach(0, True, {})
    assert succ


autocmd("BufNew") << f"lua {_sub.name}()"
