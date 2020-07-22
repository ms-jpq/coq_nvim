from os import linesep
from typing import Any, Dict, Sequence, Tuple, cast

from pynvim import Nvim

from .types import Payload


def replace_lines(nvim: Nvim, payload: Payload) -> None:
    row, col = payload.row, payload.col
    old_prefix, new_prefix = payload.old_prefix, payload.new_prefix
    old_suffix, new_suffix = payload.old_suffix, payload.new_suffix

    old_lc, new_lc = old_prefix.count(linesep), old_suffix.count(linesep)
    btm_idx = row - old_lc
    top_idx = row + new_lc + 1

    buf = nvim.api.get_current_buf()
    old_lines: Sequence[str] = nvim.api.buf_get_lines(buf, btm_idx, top_idx, True)

    def pre_post() -> Tuple[str, str]:
        idx = sum(map(len, old_lines[:old_lc])) + col
        old = "".join(old_lines)
        pre = old[: idx - len(old_prefix)]
        post = old[idx + len(old_suffix) :]
        return pre, post

    pre, post = pre_post()
    before = pre + new_prefix
    after = new_suffix + post
    new_lines = (before + after).splitlines()

    def pos() -> Tuple[int, int]:
        idx = before.rfind(linesep)
        row = btm_idx + before.count(linesep) + 1
        col = len(before) - (0 if idx == -1 else idx)
        return row, col

    new_row, new_col = pos()

    nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)
    win = nvim.api.get_current_win()
    nvim.api.win_set_cursor(win, (new_row, new_col))
    # nvim.api.buf_set_var(buf, "_buf_cursor_pos_", new_col)


def apply_patch(nvim: Nvim, comp: Dict[str, Any]) -> None:
    data = comp.get("user_data")
    if type(data) == dict:
        try:
            payload = Payload(**cast(dict, data))
        except TypeError:
            pass
        else:
            replace_lines(nvim, payload=payload)
