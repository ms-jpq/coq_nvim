from pynvim import Nvim
from pynvim_pp.api import buf_get_var, cur_buf

from ...registry import rpc
from ..rt_types import Stack
from ..state import Repeat, state


@rpc(blocking=True)
def dot_repeat(nvim: Nvim, stack: Stack) -> None:
    buf = cur_buf(nvim)
    tick: int = buf_get_var(nvim, buf=buf, key="changedtick") or -1
    rep = state().repeat
    if tick == rep.tick:
        nvim.api.paste(rep.text, True, -1)
        new_rep = Repeat(buf=rep.buf, tick=tick + 1, text=rep.text)
        state(repeat=new_rep)
    else:
        nvim.command("norm! .")
