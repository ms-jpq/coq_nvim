from os import linesep
from typing import Any, Dict, Sequence, Tuple, cast

from pynvim import Nvim

from .types import Payload


def replace_lines(nvim: Nvim, payload: Payload) -> None:
    row = payload.row - 1
    col = payload.col
    old_prefix = payload.old_prefix
    new_prefix = payload.new_prefix
    old_suffix = payload.old_suffix
    new_suffix = payload.new_suffix

    btm_idx = row - old_prefix.count(linesep)
    top_idx = row + old_suffix.count(linesep) + 1

    buf = nvim.api.get_current_buf()
    old_lines: Sequence[str] = nvim.api.buf_get_lines(buf, btm_idx, top_idx, True)

    def seek() -> int:
        i = 0
        for r, line in enumerate(old_lines, btm_idx):
            for c, _ in enumerate(line, 0):
                if r == row and c == col:
                    return i
                else:
                    i += 1
        return i

    idx = seek()
    old = "".join(old_lines)
    pre = old[: idx - len(new_prefix)]
    post = old[idx + len(new_suffix) + 1 :]
    new_lines = (pre + new_prefix + new_suffix + post).splitlines()

    def seek2() -> Tuple[int, int]:
        cutoff = len(pre) + len(new_prefix)
        i = 0
        for r, line in enumerate(new_lines, btm_idx):
            for c, _ in enumerate(line, 0):
                if i == cutoff:
                    return r, c
                else:
                    i += 1
        return -1, -1

    new_row, new_col = seek2()

    nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)
    win = nvim.api.get_current_win()
    nvim.api.win_set_cursor(win, (new_row, new_col))


def patch(nvim: Nvim, comp: Dict[str, Any]) -> None:
    data = comp.get("user_data")
    if type(data) == dict:
        try:
            payload = Payload(**cast(dict, data))
        except TypeError:
            pass
        else:
            replace_lines(nvim, payload=payload)
