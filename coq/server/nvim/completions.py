from dataclasses import dataclass
from typing import Any, Iterable, Optional, Sequence, Tuple
from uuid import UUID

from pynvim import Nvim
from std2.pickle import new_encoder

from ...shared.types import Doc, Extern, PrimaryEdit, RangeEdit


@dataclass(frozen=True)
class UserData:
    uid: UUID
    instance: UUID
    sort_by: str
    change_uid: UUID
    primary_edit: PrimaryEdit
    secondary_edits: Sequence[RangeEdit]
    doc: Optional[Doc]
    extern: Optional[Tuple[Extern, Any]]


@dataclass(frozen=True)
class VimCompletion:
    word: Optional[str] = None
    abbr: Optional[str] = None
    menu: Optional[str] = None
    info: Optional[str] = None
    kind: Optional[str] = None
    icase: Optional[int] = None
    equal: Optional[int] = None
    dup: Optional[int] = None
    empty: Optional[int] = None
    user_data: Optional[UserData] = None


_LUA = """
(function(col, items)
  vim.schedule(
    function()
      local legal_modes = {
        ["i"] = true,
        ["ic"] = true,
        ["ix"] = true
      }
      local legal_cmodes = {
        [""] = true,
        ["eval"] = true,
        ["function"] = true,
        ["ctrl_x"] = true
      }
      local mode = vim.api.nvim_get_mode().mode
      local comp_mode = vim.fn.complete_info({"mode"}).mode
      if legal_modes[mode] and legal_cmodes[comp_mode] then
        -- when `#items ~= 0` there is something to show
        -- when `#items == 0` but `comp_mode == "eval"` there is something to close
        if #items ~= 0 or comp_mode == "eval" then
          vim.fn.complete(col, items)
        end
      end
    end
  )
end)(...)
"""

_ENCODER = new_encoder[Iterable[VimCompletion]](Iterable[VimCompletion])


def complete(nvim: Nvim, col: int, comp: Iterable[VimCompletion]) -> None:
    serialized = tuple(
        {k: v for k, v in cmp.items() if v is not None} for cmp in _ENCODER(comp)
    )
    nvim.api.exec_lua(_LUA, (col + 1, serialized))
