from os import linesep
from typing import Any, Dict, Sequence, Tuple, cast

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.window import Window

from .types import Edit, Payload, Position


def perform_edit(nvim: Nvim, buf: Buffer, edit: Edit) -> None:
    b_row, b_col = edit.begin.row, edit.begin.col
    e_row, e_col = edit.end.row, edit.end.col
    btm_idx, top_idx = b_row, e_row + 1

    old_lines: Sequence[str] = nvim.api.buf_get_lines(buf, btm_idx, top_idx, True)
    btm_line, top_line = old_lines[0][:b_col], old_lines[-1][e_col + 1 :]
    new_lines = "".join((btm_line, edit.new_text, top_line)).splitlines()
    nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)


def replace_lines(nvim: Nvim, payload: Payload) -> None:
    nvim.api.out_write(str(payload) + "\n")
    row, col = payload.position.row, payload.position.col
    old_prefix, new_prefix = payload.old_prefix, payload.new_prefix
    old_suffix, new_suffix = payload.old_suffix, payload.new_suffix

    old_lc, new_lc = old_prefix.count(linesep), old_suffix.count(linesep)
    btm_idx, top_idx = row - old_lc, row + new_lc + 1

    win: Window = nvim.api.get_current_win()
    buf: Buffer = nvim.api.get_current_buf()
    for edit in payload.edits:
        perform_edit(nvim, buf=buf, edit=edit)

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
    nvim.api.win_set_cursor(win, (new_row, new_col))
    # nvim.api.buf_set_var(buf, "_buf_cursor_pos_", new_col)


def apply_patch(nvim: Nvim, comp: Dict[str, Any]) -> None:
    data = comp.get("user_data")
    d = cast(dict, data)
    try:
        position = Position(**d["position"])
        edits = tuple(
            Edit(
                begin=Position(row=edit["begin"]["row"], col=edit["begin"]["col"]),
                end=Position(row=edit["end"]["row"], col=edit["end"]["col"]),
                new_text=edit["new_text"],
            )
            for edit in d["edits"]
        )
        payload = Payload(**{**d, **dict(position=position, edits=edits)})
    except (KeyError, TypeError):
        pass
    else:
        replace_lines(nvim, payload=payload)
