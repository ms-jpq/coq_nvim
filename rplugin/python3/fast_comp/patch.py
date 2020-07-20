from os import linesep
from typing import Any, Dict, Iterable, Sequence, cast

from pynvim import Nvim

from .types import Payload


def replace_lines(nvim: Nvim, payload: Payload) -> None:
    row = payload.row - 1
    col = payload.col
    old_prefix = payload.old_prefix
    new_prefix = payload.new_prefix
    old_suffix = payload.old_suffix
    new_suffix = payload.new_suffix

    old_lc = old_prefix.count(linesep)
    new_lc = old_suffix.count(linesep)
    btm_idx = row - old_lc
    top_idx = row + new_lc + 1

    buf = nvim.api.get_current_buf()
    old_lines: Sequence[str] = nvim.api.buf_get_lines(buf, btm_idx, top_idx, True)

    def find_idx() -> Iterable[int]:
        for r, line_len in enumerate(map(len, old_lines)):
            if r < old_lc:
                yield line_len
            else:
                yield col
                break

    idx = sum(find_idx())

    old = "".join(old_lines)
    pre = old[: idx - len(old_prefix)]
    post = old[idx + len(old_suffix) + 1 :]
    before = pre + new_prefix
    after = new_suffix + post
    new_lines = (before + after).splitlines()

    r_idx = before.rfind(linesep)
    new_row = btm_idx + before.count(linesep) + 1
    new_col = len(before) - (0 if r_idx == -1 else r_idx)

    nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)
    win = nvim.api.get_current_win()
    nvim.api.win_set_cursor(win, (new_row, new_col))

    msg = f"{[pre]} - {[post]}"
    nvim.api.out_write(msg + "\n")


def patch(nvim: Nvim, comp: Dict[str, Any]) -> None:
    data = comp.get("user_data")
    if type(data) == dict:
        try:
            payload = Payload(**cast(dict, data))
        except TypeError:
            pass
        else:
            replace_lines(nvim, payload=payload)
